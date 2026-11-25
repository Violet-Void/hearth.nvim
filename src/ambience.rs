//! Procedural ambience: fire, snow wind and water, synthesised in real time.
//!
//! Each layer is an infinite mono `rodio::Source` on its own `Sink`, so layers
//! start, stop and change volume independently. Everything is lowpass-heavy and
//! warm; nothing is sampled from files.

use rodio::source::Source;
use rodio::{nz, ChannelCount, Player as RodioPlayer, SampleRate};
use std::collections::BTreeMap;
use std::f32::consts::PI;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub const SAMPLE_RATE: u32 = 44_100;
const SAMPLE_RATE_NZ: SampleRate = std::num::NonZeroU32::new(SAMPLE_RATE).unwrap();
const SR: f32 = SAMPLE_RATE as f32;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Layer {
    Fire,
    Wind,
    Water,
}

impl Layer {
    pub const ALL: [Layer; 3] = [Layer::Fire, Layer::Wind, Layer::Water];

    pub fn name(self) -> &'static str {
        match self {
            Layer::Fire => "fire",
            Layer::Wind => "wind",
            Layer::Water => "water",
        }
    }

    pub fn parse(name: &str) -> Option<Layer> {
        Layer::ALL.into_iter().find(|l| l.name() == name)
    }

    fn default_seed(self) -> u64 {
        match self {
            Layer::Fire => 0x9E37_79B9_7F4A_7C15,
            Layer::Wind => 0xC2B2_AE3D_27D4_EB4F,
            Layer::Water => 0x1656_67B1_9E37_79F9,
        }
    }
}

// ---------------------------------------------------------------------------
// Small DSP building blocks
// ---------------------------------------------------------------------------

struct Rng(u64);

impl Rng {
    fn new(seed: u64) -> Self {
        Rng(seed | 1)
    }
    fn next_u64(&mut self) -> u64 {
        // xorshift64*
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    /// Uniform in [0, 1).
    fn unit(&mut self) -> f32 {
        (self.next_u64() >> 40) as f32 / (1u64 << 24) as f32
    }
    /// Uniform in [-1, 1).
    fn signed(&mut self) -> f32 {
        self.unit() * 2.0 - 1.0
    }
    fn range(&mut self, lo: f32, hi: f32) -> f32 {
        lo + (hi - lo) * self.unit()
    }
}

/// One-pole lowpass coefficient for cutoff `fc`.
fn lp_coeff(fc: f32) -> f32 {
    1.0 - (-2.0 * PI * fc / SR).exp()
}

/// Gain that restores unit variance to white noise through a one-pole lowpass.
fn lp_norm(a: f32) -> f32 {
    ((2.0 - a) / a).sqrt()
}

struct OnePole {
    a: f32,
    y: f32,
}

impl OnePole {
    fn new(fc: f32) -> Self {
        OnePole {
            a: lp_coeff(fc),
            y: 0.0,
        }
    }
    fn set_cutoff(&mut self, fc: f32) {
        self.a = lp_coeff(fc);
    }
    fn process(&mut self, x: f32) -> f32 {
        self.y += self.a * (x - self.y);
        self.y
    }
}

/// Chamberlin state-variable filter, bandpass output.
struct Bandpass {
    low: f32,
    band: f32,
    f: f32,
    q: f32,
}

impl Bandpass {
    fn new(fc: f32, q: f32) -> Self {
        let mut b = Bandpass {
            low: 0.0,
            band: 0.0,
            f: 0.0,
            q: 1.0 / q,
        };
        b.set_cutoff(fc);
        b
    }
    fn set_cutoff(&mut self, fc: f32) {
        self.f = 2.0 * (PI * fc / SR).sin();
    }
    fn process(&mut self, x: f32) -> f32 {
        self.low += self.f * self.band;
        let high = x - self.low - self.q * self.band;
        self.band += self.f * high;
        self.band
    }
}

/// Soft clip: keeps output strictly inside (-1, 1).
fn soft_clip(x: f32) -> f32 {
    x.tanh()
}

// ---------------------------------------------------------------------------
// Layers
// ---------------------------------------------------------------------------

trait Dsp: Send {
    fn next(&mut self) -> f32;
}

/// Wood stove: warm brown-ish rumble, soft hiss, random crackle pops.
struct Fire {
    rng: Rng,
    rumble: OnePole,
    rumble_gain: f32,
    hiss: OnePole,
    hiss_gain: f32,
    pop_tone: OnePole,
    pop_env: f32,
    pop_amp: f32,
    intensity: f32,
    intensity_target: f32,
    retarget_in: u32,
}

impl Fire {
    fn new(seed: u64) -> Self {
        let rumble = OnePole::new(110.0);
        let hiss = OnePole::new(1400.0);
        Fire {
            rng: Rng::new(seed),
            rumble_gain: lp_norm(rumble.a),
            rumble,
            hiss_gain: lp_norm(hiss.a),
            hiss,
            pop_tone: OnePole::new(2600.0),
            pop_env: 0.0,
            pop_amp: 0.0,
            intensity: 0.5,
            intensity_target: 0.5,
            retarget_in: 0,
        }
    }
}

impl Dsp for Fire {
    fn next(&mut self) -> f32 {
        // The flame breathes: pick a new intensity every 0.5-2.5 s, glide to it.
        if self.retarget_in == 0 {
            self.intensity_target = self.rng.range(0.25, 1.0);
            self.retarget_in = (self.rng.range(0.5, 2.5) * SR) as u32;
        }
        self.retarget_in -= 1;
        self.intensity += (self.intensity_target - self.intensity) * 0.00005;

        let white = self.rng.signed();
        let rumble = self.rumble.process(white) * self.rumble_gain * (0.20 + 0.10 * self.intensity);
        let hiss = self.hiss.process(self.rng.signed()) * self.hiss_gain * 0.035 * self.intensity;

        // Poisson crackle, ~3-14 pops/s depending on intensity.
        let rate = 3.0 + 11.0 * self.intensity;
        if self.rng.unit() < rate / SR {
            self.pop_amp = self.rng.range(0.25, 1.0);
            self.pop_env = 1.0;
        }
        let pop = self.pop_tone.process(self.rng.signed()) * self.pop_env * self.pop_amp * 2.2;
        self.pop_env *= 0.9965; // ~6 ms time constant
        if self.pop_env < 1e-4 {
            self.pop_env = 0.0;
        }

        soft_clip(rumble + hiss + pop)
    }
}

/// Snow wind: lowpassed noise whose cutoff and level swell with slow gusts.
struct Wind {
    rng: Rng,
    stage1: OnePole,
    stage2: OnePole,
    phase_a: f32,
    phase_b: f32,
    step: u32,
    gust: f32,
}

impl Wind {
    fn new(seed: u64) -> Self {
        let mut rng = Rng::new(seed);
        Wind {
            phase_a: rng.range(0.0, 2.0 * PI),
            phase_b: rng.range(0.0, 2.0 * PI),
            rng,
            stage1: OnePole::new(300.0),
            stage2: OnePole::new(300.0),
            step: 0,
            gust: 0.5,
        }
    }
}

impl Dsp for Wind {
    fn next(&mut self) -> f32 {
        // Control rate: update gust and cutoffs every 64 samples.
        if self.step % 64 == 0 {
            self.phase_a += 2.0 * PI * 0.055 * 64.0 / SR;
            self.phase_b += 2.0 * PI * 0.13 * 64.0 / SR;
            self.gust = 0.5 + 0.30 * self.phase_a.sin() + 0.20 * self.phase_b.sin();
            let fc = 140.0 + 520.0 * self.gust;
            self.stage1.set_cutoff(fc);
            self.stage2.set_cutoff(fc * 1.3);
        }
        self.step = self.step.wrapping_add(1);

        let white = self.rng.signed();
        let s = self.stage2.process(self.stage1.process(white));
        // Two cascaded one-poles: normalise empirically (std of s ~ 0.04..0.12).
        let level = 0.25 + 0.75 * self.gust;
        soft_clip(s * 3.3 * level)
    }
}

/// Water: bandpassed noise with a drifting centre plus soft droplets.
struct Water {
    rng: Rng,
    band: Bandpass,
    lfo: f32,
    step: u32,
    drop_phase: f32,
    drop_freq: f32,
    drop_env: f32,
    drop_amp: f32,
    drop_tone: OnePole,
}

impl Water {
    fn new(seed: u64) -> Self {
        let mut rng = Rng::new(seed);
        Water {
            lfo: rng.range(0.0, 2.0 * PI),
            rng,
            band: Bandpass::new(700.0, 1.4),
            step: 0,
            drop_phase: 0.0,
            drop_freq: 800.0,
            drop_env: 0.0,
            drop_amp: 0.0,
            drop_tone: OnePole::new(2200.0),
        }
    }
}

impl Dsp for Water {
    fn next(&mut self) -> f32 {
        if self.step % 64 == 0 {
            self.lfo += 2.0 * PI * 0.31 * 64.0 / SR;
            self.band.set_cutoff(650.0 + 260.0 * self.lfo.sin());
        }
        self.step = self.step.wrapping_add(1);

        let flow = self.band.process(self.rng.signed()) * 0.60;

        // Droplets: short rising sine blips, ~3 per second.
        if self.rng.unit() < 3.0 / SR {
            self.drop_freq = self.rng.range(500.0, 1100.0);
            self.drop_amp = self.rng.range(0.12, 0.30);
            self.drop_env = 1.0;
            self.drop_phase = 0.0;
        }
        let mut drop = 0.0;
        if self.drop_env > 0.0 {
            self.drop_phase += 2.0 * PI * self.drop_freq / SR;
            if self.drop_phase > 2.0 * PI {
                self.drop_phase -= 2.0 * PI;
            }
            self.drop_freq *= 1.00035; // upward chirp
            drop =
                self.drop_tone.process(self.drop_phase.sin()) * self.drop_env * self.drop_amp * 1.5;
            self.drop_env *= 0.9992; // ~30 ms time constant
            if self.drop_env < 1e-4 {
                self.drop_env = 0.0;
            }
        }

        soft_clip(flow + drop)
    }
}

fn make_dsp(layer: Layer, seed: u64) -> Box<dyn Dsp> {
    match layer {
        Layer::Fire => Box::new(Fire::new(seed)),
        Layer::Wind => Box::new(Wind::new(seed)),
        Layer::Water => Box::new(Water::new(seed)),
    }
}

// ---------------------------------------------------------------------------
// Source, control and engine
// ---------------------------------------------------------------------------

/// Shared live controls for one running layer.
pub struct Control {
    volume_bits: AtomicU32,
    stop: AtomicBool,
}

impl Control {
    fn new(volume: f32) -> Self {
        Control {
            volume_bits: AtomicU32::new(clamp_volume(volume).to_bits()),
            stop: AtomicBool::new(false),
        }
    }
    pub fn volume(&self) -> f32 {
        f32::from_bits(self.volume_bits.load(Ordering::Relaxed))
    }
    pub fn set_volume(&self, volume: f32) {
        self.volume_bits
            .store(clamp_volume(volume).to_bits(), Ordering::Relaxed);
    }
    fn request_stop(&self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

pub fn clamp_volume(volume: f32) -> f32 {
    if volume.is_nan() {
        0.0
    } else {
        volume.clamp(0.0, 1.0)
    }
}

/// Infinite mono source. Volume changes, fade-in and fade-out are smoothed
/// (~45 ms) so nothing clicks; the source ends once a requested stop has faded out.
pub struct LayerSource {
    dsp: Box<dyn Dsp>,
    ctl: Arc<Control>,
    gain: f32,
}

impl LayerSource {
    pub fn new(layer: Layer, seed: u64, ctl: Arc<Control>) -> Self {
        LayerSource {
            dsp: make_dsp(layer, seed),
            ctl,
            gain: 0.0,
        }
    }
}

impl Iterator for LayerSource {
    type Item = f32;

    fn next(&mut self) -> Option<f32> {
        let stopping = self.ctl.stop.load(Ordering::Relaxed);
        let target = if stopping { 0.0 } else { self.ctl.volume() };
        self.gain += (target - self.gain) * 0.0005;
        if stopping && self.gain < 1e-4 {
            return None;
        }
        // While muted, keep emitting silence without advancing the procedural DSP.
        if target <= 0.0 && self.gain < 1e-4 {
            return Some(0.0);
        }
        Some(self.dsp.next() * self.gain)
    }
}

impl Source for LayerSource {
    fn current_span_len(&self) -> Option<usize> {
        None
    }
    fn channels(&self) -> ChannelCount {
        nz!(1)
    }
    fn sample_rate(&self) -> SampleRate {
        SAMPLE_RATE_NZ
    }
    fn total_duration(&self) -> Option<Duration> {
        None
    }
}

struct Running {
    sink: RodioPlayer,
    ctl: Arc<Control>,
}

/// Owns the running layers.
#[derive(Default)]
pub struct Ambience {
    layers: Mutex<BTreeMap<Layer, Running>>,
}

impl Ambience {
    pub fn new() -> Self {
        Self::default()
    }

    /// Start a layer, or just update its volume if it is already running.
    pub fn start<F>(&self, make_player: F, layer: Layer, volume: f32) -> Result<(), String>
    where
        F: FnOnce() -> Result<RodioPlayer, String>,
    {
        let mut layers = self.layers.lock().map_err(|e| e.to_string())?;
        if let Some(running) = layers.get(&layer) {
            running.ctl.set_volume(volume);
            return Ok(());
        }
        let sink = make_player()?;
        let ctl = Arc::new(Control::new(volume));
        sink.append(LayerSource::new(layer, layer.default_seed(), ctl.clone()));
        layers.insert(layer, Running { sink, ctl });
        Ok(())
    }

    /// Fade out and release one layer, or all of them when `layer` is `None`.
    /// Returns the layers that were running.
    pub fn stop(&self, layer: Option<Layer>) -> Vec<Layer> {
        let Ok(mut layers) = self.layers.lock() else {
            return vec![];
        };
        let targets: Vec<Layer> = match layer {
            Some(l) if layers.contains_key(&l) => vec![l],
            Some(_) => vec![],
            None => layers.keys().copied().collect(),
        };
        for l in &targets {
            if let Some(running) = layers.remove(l) {
                running.ctl.request_stop();
                running.sink.detach(); // keep playing until the fade-out ends
            }
        }
        targets
    }

    /// Set the volume of one layer or all running layers. Returns how many changed.
    pub fn set_volume(&self, layer: Option<Layer>, volume: f32) -> usize {
        let Ok(layers) = self.layers.lock() else {
            return 0;
        };
        let mut changed = 0;
        for (l, running) in layers.iter() {
            if layer.is_none() || layer == Some(*l) {
                running.ctl.set_volume(volume);
                changed += 1;
            }
        }
        changed
    }

    /// Running layers and their target volumes.
    pub fn status(&self) -> Vec<(Layer, f32)> {
        let Ok(mut layers) = self.layers.lock() else {
            return vec![];
        };
        layers.retain(|_, r| !r.sink.empty());
        layers.iter().map(|(l, r)| (*l, r.ctl.volume())).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn render(layer: Layer, seed: u64, volume: f32, secs: f32) -> Vec<f32> {
        let ctl = Arc::new(Control::new(volume));
        let src = LayerSource::new(layer, seed, ctl);
        src.take((secs * SR) as usize).collect()
    }

    fn rms(x: &[f32]) -> f32 {
        (x.iter().map(|s| s * s).sum::<f32>() / x.len() as f32).sqrt()
    }

    /// Ratio of first-difference energy to signal energy: ~1.41 for white
    /// noise, small for lowpassed material.
    fn brightness(x: &[f32]) -> f32 {
        let d: Vec<f32> = x.windows(2).map(|w| w[1] - w[0]).collect();
        rms(&d) / rms(x)
    }

    #[test]
    fn layer_names_round_trip() {
        for l in Layer::ALL {
            assert_eq!(Layer::parse(l.name()), Some(l));
        }
        assert_eq!(Layer::parse("lava"), None);
    }

    #[test]
    fn volume_is_clamped() {
        let c = Control::new(5.0);
        assert_eq!(c.volume(), 1.0);
        c.set_volume(-1.0);
        assert_eq!(c.volume(), 0.0);
        c.set_volume(f32::NAN);
        assert_eq!(c.volume(), 0.0);
    }

    #[test]
    fn layers_are_finite_bounded_and_audible() {
        for l in Layer::ALL {
            // Skip the 45 ms fade-in when measuring level.
            let x = render(l, l.default_seed(), 1.0, 8.0);
            assert!(
                x.iter().all(|s| s.is_finite() && s.abs() < 1.0),
                "{l:?} out of range"
            );
            let level = rms(&x[SAMPLE_RATE as usize..]);
            assert!(level > 0.02 && level < 0.5, "{l:?} rms {level}");
        }
    }

    #[test]
    fn output_is_deterministic_per_seed() {
        let a = render(Layer::Fire, 7, 1.0, 1.0);
        let b = render(Layer::Fire, 7, 1.0, 1.0);
        let c = render(Layer::Fire, 8, 1.0, 1.0);
        assert_eq!(a, b);
        assert_ne!(a, c);
    }

    #[test]
    fn layers_are_warm_not_hissy() {
        for (l, max) in [(Layer::Fire, 0.5), (Layer::Wind, 0.3), (Layer::Water, 0.8)] {
            let x = render(l, l.default_seed(), 1.0, 8.0);
            let b = brightness(&x[SAMPLE_RATE as usize..]);
            assert!(b < max, "{l:?} brightness {b} >= {max}");
        }
    }

    #[test]
    fn fire_crackles() {
        let x = render(Layer::Fire, Layer::Fire.default_seed(), 1.0, 10.0);
        let x = &x[SAMPLE_RATE as usize..];
        let peak = x.iter().fold(0.0f32, |m, s| m.max(s.abs()));
        assert!(peak / rms(x) > 3.0, "crest factor {}", peak / rms(x));
    }

    #[test]
    fn wind_swells() {
        let x = render(Layer::Wind, Layer::Wind.default_seed(), 1.0, 30.0);
        let win = SAMPLE_RATE as usize;
        let levels: Vec<f32> = x[win..].chunks(win).map(rms).collect();
        let (lo, hi) = levels
            .iter()
            .fold((f32::MAX, 0.0f32), |(lo, hi), l| (lo.min(*l), hi.max(*l)));
        assert!(hi / lo > 1.5, "gust range {lo}..{hi}");
    }

    #[test]
    fn zero_volume_is_silent() {
        for l in Layer::ALL {
            assert!(render(l, 1, 0.0, 0.5).iter().all(|s| *s == 0.0));
        }
    }

    #[test]
    fn muted_layer_emits_silence_and_resumes() {
        let ctl = Arc::new(Control::new(1.0));
        let mut src = LayerSource::new(Layer::Wind, 3, ctl.clone());
        for _ in 0..SAMPLE_RATE {
            assert!(src.next().is_some());
        }

        ctl.set_volume(0.0);
        let muted: Vec<f32> = src.by_ref().take(SAMPLE_RATE as usize).collect();
        assert!(
            muted[muted.len() - 100..].iter().all(|s| *s == 0.0),
            "muted layer still produced samples"
        );

        ctl.set_volume(1.0);
        let resumed: Vec<f32> = src.by_ref().take(SAMPLE_RATE as usize).collect();
        assert!(
            rms(&resumed) > 0.005,
            "did not resume: rms {}",
            rms(&resumed)
        );
    }

    #[test]
    fn volume_scales_output() {
        let loud = rms(&render(Layer::Wind, 3, 0.8, 3.0)[SAMPLE_RATE as usize..]);
        let quiet = rms(&render(Layer::Wind, 3, 0.2, 3.0)[SAMPLE_RATE as usize..]);
        assert!(loud > quiet * 3.0, "{loud} vs {quiet}");
    }

    #[test]
    fn stop_fades_out_and_ends() {
        let ctl = Arc::new(Control::new(0.5));
        let mut src = LayerSource::new(Layer::Water, 1, ctl.clone());
        for _ in 0..SAMPLE_RATE {
            assert!(src.next().is_some());
        }
        ctl.request_stop();
        let mut n = 0;
        while src.next().is_some() {
            n += 1;
            assert!(n < SAMPLE_RATE, "never ended");
        }
        assert!(n > 100, "ended abruptly after {n} samples");
    }

    #[test]
    fn long_run_stays_stable() {
        for l in Layer::ALL {
            let ctl = Arc::new(Control::new(1.0));
            let src = LayerSource::new(l, 5, ctl);
            assert!(src
                .take(SAMPLE_RATE as usize * 120)
                .all(|s| s.is_finite() && s.abs() < 1.0));
        }
    }
}
