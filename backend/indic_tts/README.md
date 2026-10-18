# Malayalam text-to-speech prototype

This folder contains the SageMaker inference handler for the AI4Bharat Malayalam
FastPitch/HiFi-GAN checkpoint. It accepts JSON with `text` and `languageCode: ml`
and returns a WAV byte stream. Only the Malayalam checkpoint is packaged initially.

The upstream checkpoint archive is approximately 1.4 GB compressed and about
1.65 GB extracted. Keep model weights out of Git. Preserve the AI4Bharat
attribution and MIT license when using the model; verify the checkpoint terms
before any public or commercial distribution.

The proposed SageMaker deployment uses an AWS-managed PyTorch inference image
and on-demand Serverless Inference with a 6 GB memory setting. The endpoint is
not created by packaging this code; do not leave any provisioned endpoint
running after a test unless its hourly cost has been explicitly reviewed.
