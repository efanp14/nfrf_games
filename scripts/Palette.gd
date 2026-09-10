class_name Palette
## Palette.gd
## Every colour in the game, declared once.
##
## Colours used to live wherever they were drawn, which meant the five player
## colours existed in three files and the road palette in two, and a change to
## one copy quietly disagreed with the others. Guardrail 7 asks for one config
## location per set of values; this is it for colour.
##
## Constants only. Nothing here holds state or is read by the model: the visual
## layer must never become the source of truth (guardrail 8). Routing, costs and
## metrics never see this file.
##
## Two groups, and the distinction matters when picking values:
##
##   CHROME  the interface around the game (menus, panels, buttons, surveys).
##           Free to carry the University of Calgary identity, because nothing
##           here encodes a quantity.
##   MAP     the city itself. These colours MEAN something (green is a painted
##           bike lane, the centre line ramps green to red with stress, each
##           player owns a hue) so they answer to legibility first and to
##           branding not at all.


# =======================================================================
#  BRAND  (University of Calgary visual identity)
# =======================================================================
## Primary. The guide asks that these two carry the identity and that accents
## stay to roughly a tenth of the area, which suits a research tool where the
## map has to stay the loudest thing on screen.
const BRAND_RED    := Color("#D6001C")
const BRAND_GOLD   := Color("#FFCD00")

## The rest of the identity, kept as the reference rather than because the game
## draws with all of it. Nothing currently reads the secondary or neutral
## entries: they are here so that a later screen reaches for an approved colour
## instead of inventing one, and so the values do not have to be looked up
## again. Do not go hunting for their call sites -- there are none by design.
##
## Secondary.
const BRAND_ORANGE_LIGHT := Color("#FFA300")
const BRAND_ORANGE_DARK  := Color("#FF671F")
const BRAND_BERRY        := Color("#9C0534")

## Accent. Both of these are in use: teal is the gain colour, pale yellow the
## selected survey bubble's border.
const BRAND_TEAL         := Color("#47A67C")
const BRAND_YELLOW_LIGHT := Color("#FFE57B")

## Neutral.
const BRAND_BLACK      := Color("#000000")
const BRAND_GREY_DARK  := Color("#6D6E71")
const BRAND_GREY_LIGHT := Color("#C7C8CA")


# =======================================================================
#  CHROME
# =======================================================================
## Buttons, panels, line edits and separators are styled by
## res://resources/ui_theme.tres, which is registered project wide and which
## mirrors these values. A .tres cannot read a GDScript constant, so the two are
## kept in step by hand and a change starts here, where the reasoning lives.
##
## Which means BRAND_RED, BRAND_GOLD, PANEL_BG, PANEL_BORDER and TEXT_PRIMARY
## look unread by a search of the GDScript and are not: the theme holds their
## values as raw numbers, and this file is where those numbers are explained.
## Change one here and change it in the .tres in the same pass.

## Warm near-black rather than the cool blue-grey this used to be, so the red and
## gold read as warm brand colours instead of as alerts on a blue field.
const PANEL_BG     := Color("#1C1A1D")
const PANEL_BORDER := Color("#3A3438")

## Three depths of scrim, by how much of the map the screen behind it should keep.
## Full takeovers hide it; the upgrade popup deliberately does not, since the
## player is deciding about the road underneath.
const OVERLAY_FULL  := Color(0.043, 0.039, 0.047, 0.97)
const OVERLAY_HEAVY := Color(0.043, 0.039, 0.047, 0.80)
const OVERLAY_LIGHT := Color(0.043, 0.039, 0.047, 0.55)

## Warm off-white, because every surface these sit on is dark. The legend's text
## was once near-black, which is a light-background colour, and against the HUD
## sidebar it came out barely legible.
const TEXT_PRIMARY := Color("#F2EFEA")
## Headings take the gold, which is the cheapest way to put the identity on every
## screen without colouring anything that carries a quantity.
const TEXT_HEADING := BRAND_GOLD
const TEXT_MUTED   := Color(1, 0.804, 0, 0.30)

## Gain and loss on round summaries and the end screen. Gain is the brand's teal
## accent rather than a plain green: teal separates from red far better under
## red-green colour deficiency. Loss is the brand red lifted in luminance, since
## #D6001C as small text on a near-black panel is too dark to read comfortably.
## Both labels carry a triangle glyph too, so hue is never the only channel.
const DELTA_GAIN := BRAND_TEAL
const DELTA_LOSS := Color("#FF4D5E")
const ERROR_TEXT := DELTA_LOSS

## Survey response bubbles. Drawn rather than left to the engine's checkbox
## icons; see SurveyScale for why the contrast here is deliberately high. A
## chosen answer fills gold, which is the strongest signal available on this
## background and matters most in the group treatment, where three people read
## one screen from different distances.
const BUBBLE_FILL            := Color("#232025")
const BUBBLE_BORDER          := Color("#8C8289")
const BUBBLE_HOVER_FILL      := Color("#3A3438")
const BUBBLE_HOVER_BORDER    := BRAND_GOLD
const BUBBLE_SELECTED_FILL   := BRAND_GOLD
const BUBBLE_SELECTED_BORDER := BRAND_YELLOW_LIGHT
const ROW_STRIPE             := Color(1.0, 1.0, 1.0, 0.035)
const SURVEY_HEADER          := BRAND_GOLD
const SURVEY_SECTION_TITLE   := BRAND_GOLD

## Safety is shown as a five-star rating. Earned stars take the brand gold; the
## rest sit at roughly the surface's own brightness so they read as empty slots
## rather than as more rating.
const STAR_EMPTY_COLOR := Color("#5A5257")


# =======================================================================
#  PLAYER IDENTITY
# =======================================================================
## One colour per seat, used for that player's home and work markers, their
## route on the map, their legend entry, their round-end bike and their rows on
## the summary screens. One list, so those can no longer drift apart.
##
## Drawn from the Okabe-Ito set, which is chosen to stay separable under the
## common forms of colour vision deficiency. Real lab participants are involved
## and roughly one man in twelve has some red-green deficiency, so a seat that
## two people cannot tell apart is a data problem, not a taste problem.
##
## No green anywhere in the list. Green belongs to painted bike lanes on the map,
## and a green route running over a green lane was the one pairing guaranteed to
## be read wrong. Yellow is out for the same reason: it would collide with the
## gold centre line and the gold safety stars.
##
## Seats 4 and 5, vermillion and orange, are the closest pair here. They only
## ever appear together at five players, which is above the group sizes actually
## run, and separating them further would have cost the other three their spacing.
##
## ORDER MATTERS AND IS NOT ALPHABETICAL OR ARBITRARY. Vermillion and reddish
## purple were swapped on 30 Aug 2026 (owner) after playtesters read seat 2 as
## clashing with the stress ramp. The ramp is
## Color.from_hsv(lerp(0.33, 0, stress), 0.85, 1.0), which passes through
## #FF8E26 at three quarters -- hue 0.08, against vermillion's 0.074. The two are
## effectively the same hue, and both land on the same road. Reddish purple sits
## far from every point on that ramp, so it takes seat 2, which is occupied in
## every group session; vermillion moves to seat 3 and orange stays at 5, so the
## ramp's near-match is only ever on screen at three or more players rather than
## at two.
const PLAYER_COLORS: Array = [
	Color("#0072B2"),   # blue
	Color("#CC79A7"),   # reddish purple
	Color("#D55E00"),   # vermillion
	Color("#56B4E9"),   # sky blue
	Color("#E69F00"),   # orange
]


## The colour for a seat, given its 0-based index. Wraps, so a group larger than
## the list still gets a colour rather than crashing.
##
## Written out as PLAYER_COLORS[i % PLAYER_COLORS.size()] in twelve places
## before this existed, one of them with an off-by-one because it was handed a
## 1-based seat number. Seat identity is the one thing the group treatment rests
## on, so it gets one accessor.
static func seat_color(seat_index: int) -> Color:
	return PLAYER_COLORS[seat_index % PLAYER_COLORS.size()]


# =======================================================================
#  MAP
# =======================================================================
## The paper the city is drawn on, set as the viewport clear colour in main.gd.
## It lives here because it is the surface every map colour is judged against,
## and because anything drawn over the map has to be legible on it: the
## round-one hint shipped invisible at 1.02:1 by inheriting the chrome text
## colour, which is built for dark cards, onto this near-white ground.
const MAP_BACKGROUND    := Color("#F6F1E6")

## Slightly warmer than a flat monochrome grey, so a road reads as asphalt
## rather than a wireframe line while staying inside the flat-vector style.
const ROAD_FILL         := Color("#3E3D42")
const ROAD_EDGE         := Color("#18171B")
const YELLOW_CENTER     := Color(0.95, 0.78, 0.18)
const WHITE_MARKING     := Color(0.95, 0.95, 0.90)
## Darkened from #2EA857 on 24 Aug 2026, owner request. Green stays the painted
## lane's colour throughout (the legend swatch reads this same constant), so
## nothing that encodes a quantity moved; this is the same cue in a deeper
## shade. Note it sits against ROAD_FILL, which is dark, so darkening the paint
## lowers its contrast with the road rather than raising it. If it reads worse
## on the map than it does here, add a light edge to the strip in LinkSegment
## rather than reverting the colour.
const BIKE_PAINT        := Color("#1B7A3C")
const PROTECTED_ASPHALT := Color("#A79C87")
## Raised from 0.45. At that alpha the glow was a faint tint six pixels either
## side of the road and read as nothing much even on a desktop.
const HOVER_GLOW        := Color(0.95, 0.75, 0.25, 0.62)
## The road the upgrade popup is open for. Opaque and gold, matching the way an
## active rail toggle is marked, because this is a state rather than a hint.
const SELECT_GLOW       := Color(1.0, 0.804, 0.0, 1.0)

## Cars cycle through a small palette instead of all being identical, so the
## traffic-as-stress cue reads as an actual street rather than repeated clones.
const CAR_COLORS: Array = [
	Color(0.82, 0.35, 0.30),
	Color(0.30, 0.46, 0.74),
	Color(0.86, 0.65, 0.22),
	Color(0.42, 0.52, 0.36),
]
const CAR_WINDOW := Color(0.65, 0.82, 0.92)
const CAR_SHADOW := Color(0.0, 0.0, 0.0, 0.20)

## Flat translucent shadows, no blur or gradient, matching the flat-vector look.
const ROAD_SHADOW := Color(0.0, 0.0, 0.0, 0.15)
const NODE_SHADOW := Color(0.0, 0.0, 0.0, 0.10)
const ICON_SHADOW := Color(0.0, 0.0, 0.0, 0.16)
## Kept low-contrast on purpose: at this map's on-screen scale a strong rim plus
## a full-radius shadow reads as an ink blot rather than a paved circle.
const NODE_RIM := Color(0.20, 0.19, 0.20, 0.55)

## Simulated residents: desaturated rather than translucent, so they read as
## background texture without competing with the player's own markers.
const NPC_HOME := Color(0.58, 0.61, 0.54)
const NPC_WORK := Color(0.46, 0.52, 0.58)

const NODE_NAME_TEXT := Color(0.45, 0.42, 0.38)
## The seat number on a player's home/work marker. Near-black INK, carried on
## an outline in that seat's own colour, rather than the seat colour drawn
## straight onto the map: the numeral sits over roads, buildings and route
## bands, and no single hue reads against all three.
const SEAT_NUMBER_TEXT := Color(0.09, 0.08, 0.10)

## The topology in play has no river, so this draws nothing today. Kept because
## CityNetwork still supports river_points.
const RIVER := Color(0.60, 0.80, 0.92, 0.35)

## Procedural background blocks. Muted enough that roads and markers stay on top
## of them visually.
const BUILDING_COLORS: Array = [
	Color(0.80, 0.72, 0.60),
	Color(0.70, 0.74, 0.68),
	Color(0.76, 0.68, 0.70),
	Color(0.70, 0.73, 0.80),
	Color(0.82, 0.78, 0.64),
]
const PARK      := Color(0.74, 0.82, 0.68)
const PARK_TREE := Color(0.47, 0.60, 0.42)
