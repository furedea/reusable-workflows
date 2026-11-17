# Changelog

## [1.5.0](https://github.com/furedea/reusable-workflows/compare/v1.4.0...v1.5.0) (2026-11-17)


### Features

* add reusable ADR lint workflow ([#33](https://github.com/furedea/reusable-workflows/issues/33)) ([780a0d1](https://github.com/furedea/reusable-workflows/commit/780a0d15fbb726a47df9119cff9bd9f3b2a5d59b))
* add reusable ast-grep workflow ([#32](https://github.com/furedea/reusable-workflows/issues/32)) ([6cc24c4](https://github.com/furedea/reusable-workflows/commit/6cc24c420db49f814f67c8bcec91867d6816e4f4))
* **review:** leave Codex and Claude findings to required_review_thread_resolution ([#31](https://github.com/furedea/reusable-workflows/issues/31)) ([7e660f7](https://github.com/furedea/reusable-workflows/commit/7e660f751fff9bddc27e361f21d6c6e12f9b6b92))

## [1.4.0](https://github.com/furedea/reusable-workflows/compare/v1.3.0...v1.4.0) (2026-11-12)


### Features

* **claude-review:** run the review on Sonnet at high effort instead of Opus at medium effort ([#27](https://github.com/furedea/reusable-workflows/issues/27)) ([f34643e](https://github.com/furedea/reusable-workflows/commit/f34643e623f278e755ec41841320184a108da7a0))

## [1.3.0](https://github.com/furedea/reusable-workflows/compare/v1.2.0...v1.3.0) (2026-11-09)


### Features

* **nix-setup:** add a composite action that installs Nix and caches the store ([#24](https://github.com/furedea/reusable-workflows/issues/24)) ([f446f69](https://github.com/furedea/reusable-workflows/commit/f446f69befc8beb9b4883baf1431a0ca7152b27a))

## [1.2.0](https://github.com/furedea/reusable-workflows/compare/v1.1.0...v1.2.0) (2026-11-09)


### Features

* **release:** add shared release-pr and release-publish workflows ([#20](https://github.com/furedea/reusable-workflows/issues/20)) ([5f7ab9f](https://github.com/furedea/reusable-workflows/commit/5f7ab9fd5fd9d8789146de4a39338980ff94d39b))

## [1.1.0](https://github.com/furedea/reusable-workflows/compare/v1.0.0...v1.1.0) (2026-11-08)


### Features

* **gha-lint:** remove the workflow-template-dir input and pin every tool version ([ecff542](https://github.com/furedea/reusable-workflows/commit/ecff542d1b8e9a1fac1c2e81335ae42afbc6f2a6))

## 1.0.0 (2026-11-08)


### Bug Fixes

* **claude-review:** keep the caller job green when the review is skipped ([#5](https://github.com/furedea/reusable-workflows/issues/5)) ([fc0cba9](https://github.com/furedea/reusable-workflows/commit/fc0cba95e88e0cdad9837bf8212d324f3cad50a5))
