# Native discovery motion

The Toronto discovery scene uses original native geometry, rendered by SwiftUI Canvas and Jetpack Compose Canvas. Its isometric loupe and bounded spring interaction were informed by [Hairline](https://github.com/lucasmarkes/hairline), reviewed at `37d2e78dcb333ab30c3338e28ed4a690364ea014`.

The lens responds only to the actual search query, clamped to its illustration bounds. It has no idle animation, timer, pointer tracking, web runtime, network service, or added dependency. iOS observes Reduce Motion; Compose animations observe the platform motion duration scale. The decorative scene is hidden from assistive technology and never intercepts touch input. Navigation keeps its touch targets stationary while the selected icon responds with a small native spring.

Hairline's React/DOM package is not imported into either native app. The following notice retains the reference project's attribution.

MIT License

Copyright (c) 2026 Lucas Marques

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
