use crate::sound::SoundParams;
use rodio::buffer::SamplesBuffer;
use rodio::cpal::traits::HostTrait;
use rodio::{nz, CpalError, DeviceSinkBuilder, MixerDeviceSink, Player as RodioPlayer};
use std::sync::{Arc, Mutex};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum PlayError {
    #[error("Audio device error: {0}")]
    Device(String),
    #[error("Playback error: {0}")]
    Playback(String),
}

static LAST_STREAM_ERROR: Mutex<Option<String>> = Mutex::new(None);

pub(crate) fn is_harmless_alsa_poll_error(msg: &str) -> bool {
    msg.contains("ALSA function 'poll' failed with error 'EINTR")
        || msg.contains("ALSA function 'poll' failed with error 'Unknown errno (-4)'")
        || msg.contains("ALSA function 'poll' failed with error 'Interrupted system call")
        || msg.contains("alsa::poll() returned POLLERR")
}

fn record_stream_error(msg: &str) {
    if is_harmless_alsa_poll_error(msg) {
        return;
    }
    let mut slot = LAST_STREAM_ERROR.lock().unwrap_or_else(|e| e.into_inner());
    *slot = Some(msg.to_string());
}

pub fn last_stream_error() -> Option<String> {
    LAST_STREAM_ERROR
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clone()
}

#[cfg(test)]
pub(crate) fn clear_last_stream_error() {
    let mut slot = LAST_STREAM_ERROR.lock().unwrap_or_else(|e| e.into_inner());
    *slot = None;
}

/// Filter harmless ALSA poll/EINTR noise on Linux Wayland/X11 sessions while recording
/// genuine stream errors for `:checkhealth hearth` instead of corrupting Neovim's stderr.
fn alsa_poll_error_callback(err: CpalError) {
    record_stream_error(&err.to_string());
}

fn try_open_sink_once() -> Result<MixerDeviceSink, PlayError> {
    let default_attempt = DeviceSinkBuilder::from_default_device().and_then(|builder| {
        builder
            .with_error_callback(alsa_poll_error_callback)
            .open_sink_or_fallback()
    });

    let mut sink = match default_attempt {
        Ok(sink) => sink,
        Err(original_err) => {
            let devices = rodio::cpal::default_host()
                .output_devices()
                .map_err(|_| PlayError::Device(original_err.to_string()))?;

            let mut opened = None;
            for device in devices {
                if device.to_string().to_lowercase().contains("null") {
                    continue;
                }
                if let Ok(builder) = DeviceSinkBuilder::from_device(device) {
                    if let Ok(sink) = builder
                        .with_error_callback(alsa_poll_error_callback)
                        .open_sink_or_fallback()
                    {
                        opened = Some(sink);
                        break;
                    }
                }
            }

            opened.ok_or_else(|| PlayError::Device(original_err.to_string()))?
        }
    };

    sink.log_on_drop(false);
    Ok(sink)
}

fn open_output_sink() -> Result<MixerDeviceSink, PlayError> {
    // Retry logic for ALSA EINTR errors
    let mut attempts = 3;
    loop {
        match try_open_sink_once() {
            Ok(sink) => return Ok(sink),
            Err(e) => {
                attempts -= 1;
                if attempts == 0 {
                    return Err(PlayError::Device(format!(
                        "Failed to create audio output stream after retries: {e}"
                    )));
                }
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
        }
    }
}

pub struct Player {
    audio_context: Arc<Mutex<Option<(MixerDeviceSink, RodioPlayer)>>>,
}

impl Player {
    pub fn new() -> Result<Self, PlayError> {
        // Lazy initialization - audio context created only when first sound is played
        // This reduces ALSA polling errors by avoiding persistent audio connections
        Ok(Self {
            audio_context: Arc::new(Mutex::new(None)),
        })
    }

    fn ensure_audio_initialized(&self) -> Result<(), PlayError> {
        let mut context = self
            .audio_context
            .lock()
            .map_err(|e| PlayError::Playback(format!("Failed to lock audio context: {}", e)))?;

        if context.is_none() {
            let sink = open_output_sink()?;
            let sfx_player = RodioPlayer::connect_new(sink.mixer());
            *context = Some((sink, sfx_player));
        }

        Ok(())
    }

    /// Connect a new independent player to the shared output mixer (for ambience layers).
    pub fn connect_ambience_player(&self) -> Result<RodioPlayer, PlayError> {
        self.ensure_audio_initialized()?;
        let context = self
            .audio_context
            .lock()
            .map_err(|e| PlayError::Playback(format!("Failed to lock audio context: {}", e)))?;
        context
            .as_ref()
            .map(|(sink, _)| RodioPlayer::connect_new(sink.mixer()))
            .ok_or_else(|| PlayError::Device("Audio output not initialised".to_string()))
    }

    pub fn play(&self, params: SoundParams) -> Result<(), PlayError> {
        self.ensure_audio_initialized()?;

        let mut generator = params.generator();

        let total_duration = (generator.sample.env_attack.powi(2)
            + generator.sample.env_sustain.powi(2)
            + generator.sample.env_decay.powi(2))
            * 100000.0;
        let buffer_size = total_duration.ceil() as usize;

        let mut buffer = vec![0.0; buffer_size];
        generator.generate(&mut buffer);

        let source = SamplesBuffer::new(nz!(1), nz!(44_100), buffer);

        let context = self
            .audio_context
            .lock()
            .map_err(|e| PlayError::Playback(format!("Failed to lock audio context: {}", e)))?;

        if let Some((_, sfx_player)) = context.as_ref() {
            sfx_player.stop();
            sfx_player.append(source);
        }

        Ok(())
    }

    pub fn append(&self, params: SoundParams) -> Result<(), PlayError> {
        self.ensure_audio_initialized()?;

        let mut generator = params.generator();

        let total_duration = (generator.sample.env_attack.powi(2)
            + generator.sample.env_sustain.powi(2)
            + generator.sample.env_decay.powi(2))
            * 100000.0;
        let buffer_size = total_duration.ceil() as usize;

        let mut buffer = vec![0.0; buffer_size];
        generator.generate(&mut buffer);

        let source = SamplesBuffer::new(nz!(1), nz!(44_100), buffer);

        let context = self
            .audio_context
            .lock()
            .map_err(|e| PlayError::Playback(format!("Failed to lock audio context: {}", e)))?;

        if let Some((_, sfx_player)) = context.as_ref() {
            sfx_player.append(source);
        }

        Ok(())
    }

    pub fn play_and_wait(&self, params: SoundParams) -> Result<(), PlayError> {
        self.append(params)?;

        let context = self
            .audio_context
            .lock()
            .map_err(|e| PlayError::Playback(format!("Failed to lock audio context: {}", e)))?;

        if let Some((_, sfx_player)) = context.as_ref() {
            sfx_player.sleep_until_end();
        }

        Ok(())
    }

    pub fn stop(&self) -> Result<(), PlayError> {
        let context = self
            .audio_context
            .lock()
            .map_err(|e| PlayError::Playback(format!("Failed to lock audio context: {}", e)))?;

        if let Some((_, sfx_player)) = context.as_ref() {
            sfx_player.stop();
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::{
        clear_last_stream_error, is_harmless_alsa_poll_error, last_stream_error, record_stream_error,
    };

    #[test]
    fn filters_harmless_alsa_poll_errors() {
        assert!(is_harmless_alsa_poll_error(
            "A backend-specific error has occurred: ALSA function 'poll' failed with error 'EINTR (Interrupted system call)'"
        ));
        assert!(is_harmless_alsa_poll_error(
            "ALSA function 'poll' failed with error 'Unknown errno (-4)'"
        ));
        assert!(is_harmless_alsa_poll_error(
            "A backend-specific error has occurred: ALSA function 'poll' failed with error 'Unknown errno (-4)'"
        ));
        assert!(is_harmless_alsa_poll_error(
            "ALSA function 'poll' failed with error 'Interrupted system call (4)'"
        ));
        assert!(is_harmless_alsa_poll_error(
            "A backend-specific error has occurred: alsa::poll() returned POLLERR"
        ));
        assert!(!is_harmless_alsa_poll_error(
            "A backend-specific error has occurred: ALSA function 'poll' failed with error 'ENODEV (No such device)'"
        ));
        assert!(!is_harmless_alsa_poll_error(
            "The requested device is no longer available"
        ));
    }

    #[test]
    fn records_only_non_harmless_stream_errors() {
        clear_last_stream_error();

        record_stream_error("ALSA function 'poll' failed with error 'Unknown errno (-4)'");
        assert_eq!(last_stream_error(), None);

        record_stream_error("The requested device is no longer available");
        assert_eq!(
            last_stream_error().as_deref(),
            Some("The requested device is no longer available")
        );

        record_stream_error("ALSA function 'poll' failed with error 'EINTR (Interrupted system call)'");
        assert_eq!(
            last_stream_error().as_deref(),
            Some("The requested device is no longer available")
        );

        clear_last_stream_error();
    }
}
