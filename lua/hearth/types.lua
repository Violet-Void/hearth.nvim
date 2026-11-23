---@alias WaveType
---| 0 # Square wave
---| 1 # Sawtooth wave
---| 2 # Sine wave
---| 3 # Noise wave
---| 4 # Triangle wave

---@class Hearth.SoundParams
---@field wave_type? WaveType Wave type (default: 0 square)
---@field base_freq? number Base frequency in Hz (default: 440)
---@field freq_limit? number Minimum frequency during slides in Hz
---@field freq_ramp? number Frequency change over time in octaves/sec
---@field freq_dramp? number Change in frequency slide in octaves/sec²
---@field duty? number Square wave duty cycle percentage (0-100)
---@field duty_ramp? number Change in duty cycle %/sec
---@field vib_strength? number Vibrato depth ±%
---@field vib_speed? number Vibrato frequency in Hz
---@field env_attack? number Attack time in seconds
---@field env_sustain? number Sustain time in seconds
---@field env_punch? number Initial volume boost percentage
---@field env_decay? number Decay time in seconds
---@field lpf_freq? number Low-pass filter cutoff frequency in Hz
---@field lpf_ramp? number Change in filter cutoff over time
---@field lpf_resonance? number Filter resonance percentage (0-100)
---@field hpf_freq? number High-pass filter cutoff frequency in Hz
---@field hpf_ramp? number Change in high-pass cutoff over time
---@field pha_offset? number Phaser offset in milliseconds
---@field pha_ramp? number Change in phaser offset msec/sec
---@field repeat_speed? number Sound repeat frequency in Hz
---@field arp_speed? number Time between arpeggio notes in seconds
---@field arp_mod? number Frequency multiplier for arpeggio
---@field sound_vol? number Sound-specific volume (0.0-1.0), modulated by master_volume

---@alias PlayCallback
---| "play" # Play immediately, interrupting current sound
---| "append" # Queue sound to play after current sounds
---| "play_and_wait" # Play and wait for completion
---| fun(sound: Hearth.SoundParams): any # Custom callback function

---@class Hearth.Sound
---@field event string Neovim event name that triggers the sound
---@field sound Hearth.SoundParams|Hearth.SoundParams[] Single sound or sequence of sounds to play
---@field callback? PlayCallback How to play the sound (default: "play")

---@class Hearth.Theme Hearth.Sound[] Array of sound configurations

---@class Hearth.BinaryConfig
---@field auto_update boolean Automatically download updates
---@field cache_timeout number Version cache timeout in seconds
---@field download_timeout number Download timeout in seconds
---@field verify_checksum boolean Verify binary checksums
---@field use_development boolean Use development build if available
---@field github_api_token string|nil GitHub API token for higher rate limits
---@field proxy Hearth.ProxyConfig Proxy configuration

---@class Hearth.ProxyConfig
---@field url string|nil Proxy URL
---@field from_env boolean Use system proxy settings

---@class Hearth.Config
---@field is_enabled boolean Whether the plugin is enabled (default: true)
---@field theme string|Hearth.Theme Theme name or custom sounds table (default: "chiptune")
---@field min_interval number Minimum interval between sounds in seconds (default: 0.05)
---@field master_volume? number Master volume for all sounds (0.0-1.0, default: 1.0)
---@field binary Hearth.BinaryConfig Binary management configuration
---@field variation? { profiles?: table<string, Hearth.VariationProfile>, cursor_cents?: table<string, number> } Variation profiles and cursor pitch offsets
---@field ambience? Hearth.AmbienceConfig Procedural ambience options
---@field debug boolean Whether to print the debug message
