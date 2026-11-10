// Offline single-process translation prototype. No sockets, tools or commands.
// Protocol: repeat big-endian u32 locale length + locale bytes + u32 input
// length + UTF-8 input bytes. EOF closes worker. One JSON line per request.
// Build against the independently verified official llama.cpp b12110 headers
// and runtime; do not redistribute either model or vendor binaries here.
#include "llama.h"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <set>
#include <string>
#include <sys/resource.h>
#include <vector>

#ifndef GTA_MODEL_GPU_LAYERS
#define GTA_MODEL_GPU_LAYERS 0
#endif
#ifndef GTA_MODEL_RSS_LIMIT
#define GTA_MODEL_RSS_LIMIT 4000000000ULL
#endif
static constexpr uint64_t MODEL_RSS_LIMIT = GTA_MODEL_RSS_LIMIT;
static uint64_t peak_rss() {
    struct rusage r{};
    if (getrusage(RUSAGE_SELF, &r) || r.ru_maxrss < 0) return UINT64_MAX;
    // Linux reports KiB, while Darwin reports bytes. This file is the
    // separate Linux runner variant and does not modify the Mac worker.
#if defined(__linux__)
    return static_cast<uint64_t>(r.ru_maxrss) * 1024ULL;
#else
    return static_cast<uint64_t>(r.ru_maxrss);
#endif
}
static double seconds(std::chrono::steady_clock::time_point t) { return std::chrono::duration<double>(std::chrono::steady_clock::now() - t).count(); }
static std::string json_string(const std::string &s) {
    std::string out = "\""; char buf[7];
    for (unsigned char c : s) {
        if (c == '"' || c == '\\') { out += '\\'; out += static_cast<char>(c); }
        else if (c < 0x20) { std::snprintf(buf, sizeof(buf), "\\u%04x", c); out += buf; }
        else out += static_cast<char>(c);
    }
    return out + '"';
}
static bool read_exact(char *p, size_t n) { return static_cast<bool>(std::cin.read(p, static_cast<std::streamsize>(n))); }
static bool read_u32(uint32_t &n) { unsigned char b[4]; if (!read_exact(reinterpret_cast<char*>(b), 4)) return false; n = (uint32_t(b[0]) << 24) | (uint32_t(b[1]) << 16) | (uint32_t(b[2]) << 8) | b[3]; return true; }
static std::vector<llama_token> tokenize(const llama_vocab *v, const std::string &s, bool add_special, bool parse_special) {
    int n = llama_tokenize(v, s.data(), static_cast<int32_t>(s.size()), nullptr, 0, add_special, parse_special);
    if (n >= 0 || n == INT32_MIN) return {};
    std::vector<llama_token> t(static_cast<size_t>(-n));
    if (llama_tokenize(v, s.data(), static_cast<int32_t>(s.size()), t.data(), static_cast<int32_t>(t.size()), add_special, parse_special) != static_cast<int>(t.size())) return {};
    return t;
}
static llama_token prefix_id(const llama_vocab *v, const std::string &prefix) {
    // The exact vocabulary entry must exist; no fallback to an unknown token.
    for (int32_t i = 0; i < llama_vocab_n_tokens(v); ++i) {
        const char *t = llama_vocab_get_text(v, i);
        if (t && prefix == t) return i;
    }
    return LLAMA_TOKEN_NULL;
}
static void emit_error(const std::string &e) { std::cout << "{\"ok\":false,\"error\":" << json_string(e) << "}" << std::endl; }

int main(int argc, char **argv) {
    if (argc != 2) { std::fprintf(stderr, "Usage: madlad_worker MODEL.gguf\n"); return 2; }
    auto init_start = std::chrono::steady_clock::now();
    llama_backend_init();
    auto mp = llama_model_default_params(); mp.n_gpu_layers = GTA_MODEL_GPU_LAYERS;
    llama_model *model = llama_model_load_from_file(argv[1], mp);
    if (!model || peak_rss() >= MODEL_RSS_LIMIT || !llama_model_has_encoder(model) || !llama_model_has_decoder(model)) { std::fprintf(stderr, "Model load/encoder/memory failed\n"); return 3; }
    const llama_vocab *vocab = llama_model_get_vocab(model);
    auto cp = llama_context_default_params(); cp.n_ctx = 512; cp.n_batch = 512; cp.n_ubatch = 512; cp.n_threads = 2; cp.n_threads_batch = 2;
    llama_context *ctx = llama_init_from_model(model, cp);
    if (!ctx || peak_rss() >= MODEL_RSS_LIMIT) { std::fprintf(stderr, "Context/memory failed\n"); return 3; }
    const auto init_seconds = seconds(init_start); const auto init_rss = peak_rss();
    std::cerr << "READY init_seconds=" << init_seconds << " peak_rss=" << init_rss << " gpu_layers=" << GTA_MODEL_GPU_LAYERS << std::endl;
    const std::set<std::string> allowed = {"pa", "ur", "ta", "tl", "fa", "gu", "bn", "hu"};
    for (;;) {
        uint32_t language_len = 0, source_len = 0;
        if (!read_u32(language_len)) { if (std::cin.eof() && std::cin.gcount() == 0) break; return 4; }
        if (!language_len || language_len > 8) return 4;
        std::string lang(language_len, '\0'); if (!read_exact(lang.data(), language_len) || !read_u32(source_len) || !source_len || source_len > 65'536) return 4;
        std::string source(source_len, '\0'); if (!read_exact(source.data(), source_len)) return 4;
        if (!allowed.count(lang)) { emit_error("Unsupported target locale"); continue; }
        // App code tl maps explicitly to the model's Filipino prefix; do not
        // silently substitute any other language, especially Cantonese.
        std::string prefix = "<2" + (lang == "tl" ? std::string("fil") : lang) + ">";
        const auto prefix_token = prefix_id(vocab, prefix);
        if (prefix_token == LLAMA_TOKEN_NULL || prefix_token <= 0) { emit_error("Exact target prefix absent"); continue; }
        // The official T5 tokenizer places a whitespace token before the
        // target prefix. Verify provider text cannot inject parsed specials,
        // then tokenize exactly as the official completion sample does.
        auto literal = tokenize(vocab, source, false, false);
        auto parsed = tokenize(vocab, source, false, true);
        if (literal.empty() || literal != parsed) { emit_error("Source contains model control tokens"); continue; }
        auto prompt = tokenize(vocab, prefix + " " + source, true, true);
        if (prompt.empty() || prompt.size() > 180) { emit_error("Source token limit or tokenizer failure"); continue; }
        bool prefix_present = false; for (auto token : prompt) if (token == prefix_token) prefix_present = true;
        if (!prefix_present) { emit_error("Exact target prefix not encoded"); continue; }
        auto start = std::chrono::steady_clock::now();
        llama_memory_clear(llama_get_memory(ctx), true);
        if (llama_encode(ctx, llama_batch_get_one(prompt.data(), static_cast<int32_t>(prompt.size()))) != 0) { emit_error("Encoder failed"); continue; }
        llama_token next = llama_model_decoder_start_token(model);
        if (next == LLAMA_TOKEN_NULL) next = llama_vocab_bos(vocab);
        if (next == LLAMA_TOKEN_NULL) { emit_error("Decoder start absent"); continue; }
        auto sp = llama_sampler_chain_default_params(); llama_sampler *sampler = llama_sampler_chain_init(sp);
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
        bool eos = false, error = false; int output_count = 0; std::string result;
        for (; output_count < 384; ++output_count) {
            if (peak_rss() >= MODEL_RSS_LIMIT) { error = true; break; }
            if (llama_decode(ctx, llama_batch_get_one(&next, 1)) != 0) { error = true; break; }
            next = llama_sampler_sample(sampler, ctx, -1);
            if (llama_vocab_is_eog(vocab, next)) { eos = next == llama_vocab_eos(vocab); break; }
            char piece[1024]; int n = llama_token_to_piece(vocab, next, piece, sizeof(piece), 0, true);
            if (n < 0 || result.size() + static_cast<size_t>(n) > 100'000) { error = true; break; }
            result.append(piece, static_cast<size_t>(n));
        }
        llama_sampler_free(sampler);
        if (error) { emit_error("Decode or memory guard failed"); if (peak_rss() >= MODEL_RSS_LIMIT) break; continue; }
        std::cout << "{\"ok\":true,\"locale\":" << json_string(lang) << ",\"prefixTokenID\":" << prefix_token
                  << ",\"targetPrefix\":" << json_string(prefix)
                  << ",\"inputTokens\":" << prompt.size() << ",\"outputTokens\":" << output_count
                  << ",\"endedNormally\":" << (eos ? "true" : "false") << ",\"hitTokenLimit\":" << (!eos && output_count == 384 ? "true" : "false")
                  << ",\"seconds\":" << seconds(start) << ",\"peakRSSBytes\":" << peak_rss()
                  << ",\"text\":" << json_string(result) << "}" << std::endl;
    }
    llama_free(ctx); llama_model_free(model); llama_backend_free(); return 0;
}
