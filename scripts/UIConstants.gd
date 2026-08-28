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

## Button theme colors (Dark Grimoire: antique leather, bronze frame, radiant gold hover)
const COLOR_BTN_FILL_NORMAL := Color(0.18, 0.13, 0.08, 1.0)
const COLOR_BTN_BORDER_NORMAL := Color(0.52, 0.38, 0.16, 1.0)
const COLOR_BTN_FILL_HOVER := Color(0.26, 0.19, 0.11, 1.0)
const COLOR_BTN_BORDER_HOVER := Color(1.0, 0.82, 0.28, 1.0)
const COLOR_BTN_GLOW_HOVER := Color(0.0, 0.0, 0.0, 0.0)
const COLOR_BTN_FILL_PRESSED := Color(0.12, 0.08, 0.05, 1.0)
const COLOR_BTN_BORDER_PRESSED := Color(0.38, 0.26, 0.10, 1.0)
const COLOR_BTN_FILL_DISABLED := Color(0.14, 0.12, 0.10, 0.60)
const COLOR_BTN_BORDER_DISABLED := Color(0.32, 0.28, 0.24, 0.40)
const COLOR_BTN_TEXT := Color(0.96, 0.92, 0.82)
const COLOR_BTN_TEXT_HOVER := Color.WHITE
const COLOR_BTN_TEXT_DISABLED := Color(0.55, 0.50, 0.44, 0.55)
const COLOR_BTN_PRIMARY_BORDER := Color(1.0, 0.82, 0.28, 1.0)
const COLOR_BTN_DANGER_BORDER := Color(0.75, 0.18, 0.14, 0.90)
const COLOR_BTN_DANGER_FILL_NORMAL := Color(0.24, 0.08, 0.08, 1.0)
const COLOR_BTN_DANGER_FILL_HOVER := Color(0.35, 0.10, 0.10, 1.0)
const COLOR_BTN_DANGER_BORDER_HOVER := Color(1.0, 0.30, 0.30, 1.0)
const COLOR_BTN_DANGER_TEXT := Color(1.0, 0.85, 0.85)

const BTN_RADIUS := 8
const BTN_BORDER_WIDTH := 2
const BTN_CONTENT_MARGIN := 6

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
const SHOP_CARD_IMAGE_POS := Vector2(4, 1)
const SHOP_STAT_PANEL_POS := Vector2(373, 129)
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
const COLOR_DROPDOWN_BG_NORMAL := Color(0.18, 0.13, 0.08, 1.0)
const COLOR_DROPDOWN_BORDER_NORMAL := Color(0.52, 0.38, 0.16, 1.0)
const COLOR_DROPDOWN_BG_HOVER := Color(0.26, 0.19, 0.11, 1.0)
const COLOR_DROPDOWN_BORDER_HOVER := Color(1.0, 0.82, 0.28, 1.0)
const COLOR_DROPDOWN_BG_PRESSED := Color(0.12, 0.08, 0.05, 1.0)
const COLOR_DROPDOWN_BORDER_PRESSED := Color(0.38, 0.26, 0.10, 1.0)
const COLOR_DROPDOWN_TEXT := Color(0.96, 0.92, 0.82)
const COLOR_DROPDOWN_TEXT_HOVER := Color.WHITE

# --------------------------------------------------------------- StartMenu

const STARTMENU_SLOT_BORDER_COLOR := Color(0, 0, 0, 0.7)
const STARTMENU_DELETE_BUTTON_FONT_SIZE := 34

## Save-slot card colors (Dark Grimoire palette)
## Normal slot fill: dark antique leather
const COLOR_SLOT_FILL := Color(0.18, 0.13, 0.08, 1.0)
## Normal slot frame: antique bronze
const COLOR_SLOT_FRAME := Color(0.52, 0.38, 0.16, 1.0)
## Hover/focus slot frame: radiant gold
const COLOR_SLOT_FRAME_HOVER := Color(1.0, 0.82, 0.28, 1.0)
## Inner decorative hairline: warm gold
const COLOR_SLOT_INNER_LINE := Color(0.84, 0.68, 0.28, 0.65)
## Slot label text: warm antique ivory
const COLOR_SLOT_TEXT := Color(0.96, 0.92, 0.82)
const SLOT_RADIUS := 14
const SLOT_BORDER_WIDTH := 4

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

const DECKSELECT_STAT_PANEL_POS := Vector2(361, 118)

# --------------------------------------------------------------- UIPanel

const COLOR_PANEL_FILL := Color(0.18, 0.13, 0.08, 0.96)
const COLOR_PANEL_FRAME := Color(0.52, 0.38, 0.16, 1.0)
const COLOR_PANEL_INNER_LINE := Color(0.84, 0.68, 0.28, 0.65)
