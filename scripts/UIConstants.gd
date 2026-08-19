extends Node
## Centralized numeric/visual UI values that a human would plausibly want to
## hand-tune later - panel/box/card sizes, margins, font sizes, colors, and
## hardcoded UI asset paths - pulled out of the ~24 procedural UI scripts so
## they don't have to be hunted down file by file. Registered as the
## `UIConstants` autoload; referenced elsewhere as `UIConstants.SOME_NAME`,
## same pattern as `StringTable.ID_SOME_STRING`.
##
## Text strings live in StringTable.gd, not here. One-off computed layout
## math (positions/sizes derived from other variables or screen size) stays
## in its own script, not here - only literal/hardcoded constants moved.
## UIButtonStyle.gd's own MARGIN/CONTENT_MARGIN/font-shrink constants are
## intentionally left in place too (tightly coupled to that file's
## fit-to-box algorithm).

# --------------------------------------------------------------- Shared / Buttons

## The single most-repeated theming color in the project: the soft drop
## shadow behind menu button/label text (font_shadow_color).
const COLOR_SHADOW_DIM := Color(0, 0, 0, 0.5)
## A lighter/greyer drop shadow, used by a few label helpers instead of the
## plain black one above.
const COLOR_SHADOW_LIGHT := Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 0.5)
## A soft, low-alpha drop shadow used behind panel readouts (CardStatPanel,
## UIPanel).
const COLOR_SHADOW_SOFT := Color(0.0, 0.0, 0.0, 0.35)
## A stronger, higher-alpha drop shadow used behind floating stat text.
const COLOR_SHADOW_STRONG := Color(0, 0, 0, 0.8)

## Gold used for coin totals/rewards across Battle and the save-slot screen.
const COLOR_GOLD := Color(1, 0.85, 0.1)

## Destructive/delete button text color triad (normal/hover/pressed), reused
## by Help's close-all and StartMenu's slot-delete buttons.
const COLOR_DANGER := Color(0.85, 0.1, 0.1)
const COLOR_DANGER_HOVER := Color(1.0, 0.25, 0.25)
const COLOR_DANGER_PRESSED := Color(0.6, 0.0, 0.0)

## Status-message brown, reused by Online's and Leaderboard's status labels.
const COLOR_STATUS_BROWN := Color(0.45, 0.18, 0.05)

## Translucent grey panel fill, reused by Shop's card slot background and
## DeckSelect's selector panel background.
const COLOR_PANEL_FILL_GRAY := Color(153.0 / 255.0, 153.0 / 255.0, 153.0 / 255.0, 127.0 / 255.0)

## The coin icon shown next to gold totals (Battle, Collection, StartMenu,
## CardView).
const ICON_COIN := "res://assets/coins_icon.png"

## Every screen's Back button sits in the same spot at the same size/font,
## by design (see Shop.gd's own comment about matching it).
const BACK_BUTTON_POS := Vector2(42, 463)
const BACK_BUTTON_SIZE := Vector2(115, 56)
const BACK_BUTTON_FONT_SIZE := 36

## The generic 36pt label/button font size used by several screens
## (Options, Opponents, menu buttons) for their body text.
const LABEL_FONT_SIZE_36 := 36

## The busy/loading spinner: identical position, size and pivot everywhere
## it appears (Battle, Shop, DeckSelect).
const BUSY_SPINNER_POS := Vector2(912, 496)
const BUSY_SPINNER_SIZE := Vector2(48, 48)
const BUSY_SPINNER_PIVOT := Vector2(24, 24)

# --------------------------------------------------------------- Battle

const BATTLE_NAME_SHADOW_COLOR := Color(0, 0, 0, 0.9)
const BATTLE_TARGET_LABEL_FONT_SIZE := 22
const BATTLE_CHAIN_LABEL_FONT_SIZE := 48
const BATTLE_VALUE_LABEL_COLOR := Color(1.0, 0.8, 0.1)
const BATTLE_COIN_REWARD_FONT_SIZE := 36
const BATTLE_END_BUTTON_FONT_SIZE := 36
const BATTLE_CARD_OWNER_FONT_SIZE := 26
const BATTLE_CARD_OWNER_COLOR := Color(213.0 / 255.0, 213.0 / 255.0, 213.0 / 255.0)
const BATTLE_TIMER_WARNING_COLOR := Color(0.62, 0.06, 0.06)

const BATTLE_INFO_PANEL_SIZE := Vector2(248, 256)
const BATTLE_END_INFO_PANEL_SIZE := Vector2(228, 224)
const BATTLE_CENTRAL_MSG_SIZE := Vector2(742, 90)
const BATTLE_DONE_BUTTON_SIZE := Vector2(122, 56)
const BATTLE_TAKEALL_BUTTON_SIZE := Vector2(158, 56)
const BATTLE_ARROW_ICON_SIZE := Vector2(64, 64)
const BATTLE_HELP_ARROW_SIZE := Vector2(159, 317)
const BATTLE_COIN_SPRITE_SIZE := Vector2(96, 96)
const BATTLE_COIN_SPRITE_PIVOT := Vector2(48, 48)

const BATTLE_BOARD_POS := Vector2(282, 7)
const BATTLE_HAND_POSITIONS := [
	Vector2(826, 68), Vector2(718, 134), Vector2(826, 208),
	Vector2(718, 283), Vector2(826, 348),
]
const BATTLE_PERGAMENA_POS := Vector2(0, 4)
const BATTLE_END_TAKEALL_MSG_POS := Vector2(40, 175)
const BATTLE_END_TAKEALL_OVERRIDE_BUTTON_POS := Vector2(401, 255)
const BATTLE_END_PL0_START := Vector2(80, 40)
const BATTLE_INFO_BKG_POS := Vector2(14, 282)
const BATTLE_END_PANEL_INFO_POS := Vector2(8, 311)
const BATTLE_END_CENTRAL_MSG_POS := Vector2(46, 226)
const BATTLE_END_DONE_BUTTON_POS := Vector2(790, 463)
const BATTLE_TAKEALL_BUTTON_POS := Vector2(795, 242)
const BATTLE_HELP_ARROW_POS := Vector2(574, 98)

# --------------------------------------------------------------- Shop

const SHOP_BUYBACK_BG_COLOR := Color(30.0 / 255.0, 30.0 / 255.0, 30.0 / 255.0, 127.0 / 255.0)
const SHOP_HELP_LABEL_FONT_SIZE := 20
const SHOP_TITLE_FONT_SIZE := 46
const SHOP_SELL_BUY_LABEL_FONT_SIZE := 50
const SHOP_COINS_LABEL_FONT_SIZE := 36
const SHOP_VALUE_LABEL_FONT_SIZE := 46
const SHOP_CARD_PANEL_POS := [
	Vector2(636, 115), Vector2(636, 160), Vector2(636, 205),
	Vector2(636, 250), Vector2(636, 295), Vector2(636, 340),
]
const SHOP_CARD_IMAGE_POS := Vector2(4, 1)
const SHOP_CARD_PRICE_POS := Vector2(167, 1)
const SHOP_PANEL_LEFT_POS := Vector2(10, 82)
const SHOP_CARD_SLOT_POS := Vector2(432, 391)
const SHOP_BUYBACK_BUTTON_POS := Vector2(744, 391)
const SHOP_HELP_LABEL_POS := Vector2(0, 79)
const SHOP_TITLE_LABEL_POS := Vector2(348, 14)
const SHOP_LABEL_SELL_POS := Vector2(67, 16)
const SHOP_LABEL_BUY_POS := Vector2(679, 16)
const SHOP_COINS_ICON_POS := Vector2(867, 463)
const SHOP_LABEL_COINS_POS := Vector2(711, 477)
const SHOP_LABEL_BUY_VALUE_POS := Vector2(530, 473)
const SHOP_LABEL_SELL_VALUE_POS := Vector2(309, 473)
const SHOP_ICON_POS := Vector2(372, 16)
const SHOP_INFO_BKG_POS := Vector2(364, 117)
const SHOP_STAT_PANEL_POS := Vector2(373, 129)
const SHOP_SELL_BUTTON_POS := Vector2(309, 417)
const SHOP_BUY_BUTTON_POS := Vector2(534, 417)
const SHOP_BUYBACK_CARD_POS := Vector2(694, 391)

# --------------------------------------------------------------- Leaderboard

const LEADERBOARD_TITLE_FONT_SIZE := 46
const LEADERBOARD_PAGE_FONT_SIZE := 28
const LEADERBOARD_STATUS_FONT_SIZE := 24
const LEADERBOARD_NAV_BUTTON_FONT_SIZE := 36

# --------------------------------------------------------------- Collection

const COLLECTION_TITLE_FONT_SIZE := 46
const COLLECTION_ROW_FONT_SIZE := 24
const COLLECTION_BIG_CARD_POS := Vector2(561, 21)
const COLLECTION_STAT_PANEL_POS := Vector2(246, 381)


# --------------------------------------------------------------- Help

const HELP_CLOSE_BUTTON_FONT_SIZE := 26
const HELP_DOT_COLOR := Color(1, 1, 1, 1.0)
const HELP_DOT_INACTIVE_ALPHA := 0.35

# --------------------------------------------------------------- MainMenu

const MAIN_MENU_BUTTON_FONT_SIZE := 46
const MAIN_MENU_ONLINE_BUTTON_FONT_SIZE := 36
const MAIN_MENU_CAT_POS := Vector2(850, 416)

# --------------------------------------------------------------- Options

const OPTIONS_TITLE_FONT_SIZE := 46
const OPTIONS_LANG_ARROW_FONT_SIZE := 30

# --------------------------------------------------------------- StartMenu

const STARTMENU_SLOT_BORDER_COLOR := Color(0, 0, 0, 0.7)
const STARTMENU_DELETE_BUTTON_FONT_SIZE := 34

# --------------------------------------------------------------- OnScreenKeyboard

const KEYBOARD_CARET_FONT_SIZE := 28
const KEYBOARD_KEY_FONT_SIZE := 20
const KEYBOARD_CARET_LABEL_POS := Vector2(20, 10)
const KEYBOARD_ROWS_START_Y := 56.0
const KEYBOARD_ACTION_ROW_START_X := 20.0

# --------------------------------------------------------------- CardView

const CARDVIEW_PRICE_FONT_SIZE := 24
const ICON_BLACK_PIXEL := "res://assets/black8x8.png"

# --------------------------------------------------------------- DeckSelect

const DECKSELECT_PLACEHOLDER_POS := [
	Vector2(237, 391), Vector2(334, 391), Vector2(431, 391),
	Vector2(528, 391), Vector2(625, 391),
]
const DECKSELECT_DECK_BAR_POS := Vector2(228, 377)
const DECKSELECT_PANEL_LEFT_POS := Vector2(0, 72)
const DECKSELECT_PANEL_RIGHT_POS := Vector2(612, 72)
const DECKSELECT_PLAY_BUTTON_POS := Vector2(798, 463)
const DECKSELECT_INFO_BKG_POS := Vector2(352, 106)
const DECKSELECT_LABEL_SELECT5_POS := Vector2(313, 10)
const DECKSELECT_LABEL_YOUR_DECK_POS := Vector2(67, 12)
const DECKSELECT_LABEL_YOUR_PREFS_POS := Vector2(679, 12)
const DECKSELECT_STAT_PANEL_POS := Vector2(361, 118)

# --------------------------------------------------------------- UIPanel

const COLOR_PANEL_FILL := Color(0.96, 0.93, 0.85, 0.94)
const COLOR_PANEL_FRAME := Color(0.42, 0.30, 0.14)
const COLOR_PANEL_INNER_LINE := Color(0.80, 0.66, 0.36, 0.75)
