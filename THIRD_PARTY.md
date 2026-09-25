# Third-party software and models

Karar is licensed under the Apache License 2.0 ([LICENSE](LICENSE)). This file lists what it
bundles and what it downloads.

## Ollaya

Karar.app contains the `ollaya` binary of [Ollaya](https://github.com/ollaya-dev/ollaya) v0.5.0
(`ollaya-darwin-arm64.tgz` from the project's GitHub release, pinned by version and SHA-256 in
[`scripts/fetch-ollaya.sh`](scripts/fetch-ollaya.sh)). Karar only re-signs it for the Hardened
Runtime. Ollaya is licensed under the Apache License 2.0, the same text as Karar's
[LICENSE](LICENSE).

`ollaya` links ONNX Runtime 1.28.0 (MIT) and the components ONNX Runtime bundles. Their notices ship
inside the app next to Ollaya's licence, and Karar ▸ About Karar opens each of them:

- `Karar.app/Contents/Resources/Ollaya/LICENSE`
- `Karar.app/Contents/Resources/Ollaya/THIRD_PARTY_NOTICES`
- `Karar.app/Contents/Resources/Ollaya/onnxruntime-ThirdPartyNotices.txt`

## Question sets

The five built-in question sets in [`Karar/Presets/`](Karar/Presets) (`triage`, `email`, `guard`,
`moderation`, `router`) are copied unchanged from Ollaya v0.5.0
(`crates/ollaya-api/src/presets/`), licensed under the Apache License 2.0.

## Models

Karar does not include or redistribute any model. When you download one, Ollaya fetches it from
the Ollaya registry (`ollaya.dev`) and its authors' Hugging Face repositories into `~/.ollaya`,
together with its licence file. The models Karar offers ([`Karar/Catalog.json`](Karar/Catalog.json)):

| Model | Source | Licence |
|---|---|---|
| `laya` (picks `laya:en` or `laya:multilingual`), `laya:en`, `laya:multilingual`, `laya:typed-decisions` | [convaiinnovations/laya](https://huggingface.co/convaiinnovations/laya) | Apache-2.0 |
| `nli:modernbert-large` | [MoritzLaurer/ModernBERT-large-zeroshot-v2.0](https://huggingface.co/MoritzLaurer/ModernBERT-large-zeroshot-v2.0) | Apache-2.0 |
| `nli` | [MoritzLaurer/deberta-v3-large-zeroshot-v2.0](https://huggingface.co/MoritzLaurer/deberta-v3-large-zeroshot-v2.0) | MIT |
| `gliclass` | [knowledgator/gliclass-instruct-large-v1.0](https://huggingface.co/knowledgator/gliclass-instruct-large-v1.0) | Apache-2.0 |
| `decider:0.8b` | [Mapika/decider-0.8b](https://huggingface.co/Mapika/decider-0.8b) | Apache-2.0 |
| `decider` | [Mapika/decider-2b](https://huggingface.co/Mapika/decider-2b) | Apache-2.0 |

Each model's own licence file (in its download) is authoritative.
