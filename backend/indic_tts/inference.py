"""SageMaker PyTorch handler for the Malayalam Indic-TTS checkpoint."""

import io
import json
import os

import numpy as np
from scipy.io.wavfile import write as write_wav
from TTS.utils.synthesizer import Synthesizer


def model_fn(model_dir):
    root = os.path.join(model_dir, "ml")
    return Synthesizer(
        tts_checkpoint=os.path.join(root, "fastpitch", "best_model.pth"),
        tts_config_path=os.path.join(root, "fastpitch", "config.json"),
        tts_speakers_file=os.path.join(root, "fastpitch", "speakers.pth"),
        tts_languages_file=None,
        vocoder_checkpoint=os.path.join(root, "hifigan", "best_model.pth"),
        vocoder_config=os.path.join(root, "hifigan", "config.json"),
        encoder_checkpoint="",
        encoder_config="",
        use_cuda=False,
    )


def input_fn(request_body, content_type):
    if content_type != "application/json":
        raise ValueError("Expected application/json input.")
    payload = json.loads(request_body)
    text = payload.get("text") if isinstance(payload, dict) else None
    language_code = payload.get("languageCode") if isinstance(payload, dict) else None
    if language_code != "ml":
        raise ValueError("Only Malayalam is enabled in this prototype.")
    if not isinstance(text, str) or not text.strip() or len(text) > 2000:
        raise ValueError("Text must be between 1 and 2,000 characters.")
    return text.strip()


def predict_fn(text, model):
    waveform = np.asarray(model.tts(text, speaker_name="female", style_wav=""))
    if waveform.size == 0:
        raise ValueError("The TTS model returned empty audio.")
    output = io.BytesIO()
    write_wav(output, model.output_sample_rate, waveform.astype(np.float32))
    return output.getvalue()


def output_fn(prediction, accept):
    if accept not in ("audio/wav", "*/*"):
        raise ValueError("Only audio/wav output is supported.")
    return prediction, "audio/wav"
