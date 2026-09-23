class_name RaceIntro
extends RefCounted

## Pre-countdown flyover length for menu-started races (19-D item 2). The
## flyover itself is presentation (RaceCamera + HUD card); Countdown only
## holds tick 3 back while it plays. Online, tutorial and automated races get
## none, time trial a short one, and the gameplay setting turns it off.

const FULL_SECONDS: float = 2.6
const TIME_TRIAL_SECONDS: float = 1.2


static func seconds_for(config: RaceConfig) -> float:
	if config == null or config.human_count() == 0:
		return 0.0
	if GameState.automation_mode or GameState.is_networked or GameState.tutorial_active:
		return 0.0
	if not bool(SettingsManager.get_setting(&"gameplay", &"race_intro", true)):
		return 0.0
	if config.race_mode == RaceConfig.RaceMode.TIME_TRIAL:
		return TIME_TRIAL_SECONDS
	return FULL_SECONDS


## Stamps the decision onto a menu-built config just before the race scene.
static func apply(config: RaceConfig) -> void:
	if config != null:
		config.intro_seconds = seconds_for(config)
