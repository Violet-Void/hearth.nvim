# Third-party licenses

## TL;DR
hearth.nvim is derived from player-one.nvim (MIT) and depends on rodio (MIT OR Apache-2.0), cpal (Apache-2.0), mlua (MIT), and sfxr-rs (MIT). Their notices must ship with every copy or binary.

---

## player-one.nvim (MIT) - https://github.com/jackplus-xyz/player-one.nvim

MIT License

Copyright (c) 2025 Jack Huang

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

---

## sfxr-rs (MIT) - https://github.com/bzar/sfxr-rs

MIT License

Copyright (c) 2018 Teemu Erkkola

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

---

## rodio (MIT OR Apache-2.0) - https://github.com/RustAudio/rodio
Used from crates.io with `default-features = false, features = ["playback"]` (no file decoders or Symphonia).

## cpal (Apache-2.0) - https://github.com/RustAudio/cpal
Used transitively via `rodio` (`playback` feature).

## mlua (MIT) - https://github.com/mlua-rs/mlua
LuaJIT bindings for Rust.

Transitive crates: run `cargo deny check licenses` (or inspect `cargo metadata`) before each release.
