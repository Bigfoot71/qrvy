module qrvy;

import std::math;
import raylib6;
import raygui;
import rlp;

// ================================
// Constants
// ================================

const String EASE_NAME = "ease_custom";   // name of the generated GLSL function

const int   MAX_POINTS = 32;
const int   GRID_MIN   = 2;
const int   GRID_MAX   = 32;

const int   TEXT_SIZE  = 10;      // UI + code text size
const float ROW_H      = 28.0f;
const float GAP        = 6.0f;
const float MARGIN     = 12.0f;
const float PLOT_PAD   = 16.0f;   // inner graph padding; so points at 0 and 1 stay visible
const float CTRL_H     = 5.0f * ROW_H + 4.0f * GAP;
const float CODE_PAD   = 8.0f;
const float CODE_GAP   = 4.0f;    // extra space between two code lines

const float HIT_POINT  = 10.0f;
const float HIT_HANDLE = 9.0f;
const float HANDLE_LEN = 46.0f;

// ================================
// State
// ================================

enum Drag
{
	NONE,
	POINT,
	HANDLE,
}

struct Context
{
	// Curve
	Point[MAX_POINTS] points;
	int               point_count;

	// Grid
	int               grid_res;       // active resolution
	int               grid_value;     // spinner value (may be mid-edit)
	bool              grid_editing;

	// Mouse interaction
	Drag              drag;
	int               drag_idx;

	// Generated GLSL (empty by default)
	DString           code;
	RLVector2         code_scroll;

	// Animation (see preview.c3)
	Preview           preview;
}

Context ctx = {
	.grid_res   = 10,
	.grid_value = 10,
	.drag_idx   = -1,
};

struct Layout
{
	RLRectangle code;
	RLRectangle graph;   // square
	RLRectangle plot;    // graph minus inner padding, square too
	RLRectangle ctrl;
}

// ================================
// App
// ================================

const RLPApp APP @RLPExport("app") =
{
	.title        = "qrvy",
	.flags        = WINDOW_RESIZABLE | VSYNC_HINT | MSAA_4X_HINT,
	.window_w     = 1152,
	.window_h     = 648,
	.target_fps   = 60,
	.audio_device = false,
};

fn void init() @RLPExport("init")
{
	rg::load_style_from_memory($embed("../embed/style_cyber.rgs"));
	ctx.code.init(mem);
	reset();
}

fn void quit() @RLPExport("quit")
{
	preview_free();
	ctx.code.free();
}

fn void tick() @RLPExport("tick")
{
	float w = (float)rl::get_screen_width();
	float h = (float)rl::get_screen_height();
	Layout l = compute_layout(w, h);

	if (ctx.preview.active) { preview_update(rl::get_frame_time()); }
	else                    { update(l); }

	rl::@drawing()
	{
		rl::clear_background(theme(RGGuiProperty.BACKGROUND_COLOR));

		bool locked = ctx.preview.active;
		if (locked) rg::lock();

		draw_code(l.code);
		draw_graph(l.graph, l.plot);
		draw_controls(l.ctrl);

		if (locked)
		{
			rg::unlock();
			preview_draw(w, h);
		}
	};
}

// ================================
// Layout
// ================================

fn Layout compute_layout(float w, float h)
{
	float col_w = math::clamp(w * 0.5f, 280.0f, math::max(280.0f, w - 220.0f));
	col_w = math::min(col_w, w - 2.0f * MARGIN);
	float x_col = w - col_w;

	// Keep the graph square; constrained by column width and available height
	float side = math::min(col_w - 2.0f * MARGIN, h - 3.0f * MARGIN - CTRL_H);
	side = math::max(side, 60.0f);

	Layout l;
	l.code  = { MARGIN, MARGIN, math::max(x_col - 2.0f * MARGIN, 10.0f), h - 2.0f * MARGIN };
	l.graph = { x_col + (col_w - side) * 0.5f, MARGIN, side, side };
	l.plot  = { l.graph.origin.x + PLOT_PAD, l.graph.origin.y + PLOT_PAD, side - 2.0f * PLOT_PAD, side - 2.0f * PLOT_PAD };
	l.ctrl  = { x_col + MARGIN, l.graph.origin.y + side + MARGIN, col_w - 2.0f * MARGIN, CTRL_H };
	return l;
}

// ================================
// Theme
// ================================

fn RLColor theme(RGGuiProperty property)
{
	return rl::get_color((uint)rg::get_style(RGGuiControl.DEFAULT, property));
}

// ================================
// Helpers
// ================================

fn bool in_rect(Vec2 p, RLRectangle r)
{
	Vec2 o = r.origin;
	Vec2 s = r.size;
	return p.x >= o.x && p.y >= o.y && p.x <= o.x + s.x && p.y <= o.y + s.y;
}

// Screen -> normalized [0,1], Y up
fn Vec2 to_norm(Vec2 p, RLRectangle r)
{
	Vec2 o = r.origin;
	Vec2 s = r.size;
	return { (p.x - o.x) / s.x, 1.0f - (p.y - o.y) / s.y };
}

// Normalized value -> grid index
fn int grid_index(float v)
{
	return (int)math::round(v * (float)ctx.grid_res);
}

fn float grid_value_of(int index)
{
	return (float)index / (float)ctx.grid_res;
}

// ================================
// Points
// ================================

fn void reset()
{
	ctx.point_count = 2;
	ctx.points[0] = { 0.0f, 0.0f, 0.0f };
	ctx.points[1] = { 1.0f, 1.0f, 0.0f };
	ctx.drag = Drag.NONE;
	ctx.drag_idx = -1;
	ctx.code.clear();
	ctx.code_scroll = { 0.0f, 0.0f };
}

fn void generate()
{
	ctx.code.clear();
	curve_to_glsl(&ctx.code, ctx.points[:ctx.point_count], EASE_NAME);
	ctx.code_scroll = { 0.0f, 0.0f };
}

fn void remove_point(int idx)
{
	for (int k = idx; k < ctx.point_count - 1; k++) ctx.points[k] = ctx.points[k + 1];
	ctx.point_count--;
}

fn void add_point(Vec2 n)
{
	if (ctx.point_count >= MAX_POINTS) return;

	int ix = grid_index(n.x);
	int iy = math::clamp(grid_index(n.y), 0, ctx.grid_res);
	if (ix <= 0 || ix >= ctx.grid_res) return; // both ends already exist

	int pos = 1;
	while (pos < ctx.point_count && grid_index(ctx.points[pos].x) < ix) pos++;
	if (pos < ctx.point_count && grid_index(ctx.points[pos].x) == ix) return; // column already used

	for (int k = ctx.point_count; k > pos; k--) ctx.points[k] = ctx.points[k - 1];
	ctx.points[pos] = { grid_value_of(ix), grid_value_of(iy), 0.0f };
	ctx.point_count++;
}

fn void move_point(int i, Vec2 n)
{
	int iy = math::clamp(grid_index(n.y), 0, ctx.grid_res);
	int ix = grid_index(ctx.points[i].x);

	// Endpoints keep x = 0 and x = 1; interior points stay sorted
	if (i > 0 && i < ctx.point_count - 1)
	{
		int lo = grid_index(ctx.points[i - 1].x) + 1;
		int hi = grid_index(ctx.points[i + 1].x) - 1;
		ix = math::max(lo, math::min(grid_index(n.x), hi));
	}

	ctx.points[i].x = grid_value_of(ix);
	ctx.points[i].y = grid_value_of(iy);
}

fn void resnap()
{
	for (int i = 0; i < ctx.point_count; i++)
	{
		ctx.points[i].x = grid_value_of(grid_index(ctx.points[i].x));
		ctx.points[i].y = grid_value_of(math::clamp(grid_index(ctx.points[i].y), 0, ctx.grid_res));
	}

	int i = 1;
	while (i < ctx.point_count)
	{
		if (grid_index(ctx.points[i].x) <= grid_index(ctx.points[i - 1].x))
		{
			if (i == ctx.point_count - 1) { remove_point(i - 1); i--; }
			else                          { remove_point(i); }
			if (i < 1) i = 1;
		}
		else
		{
			i++;
		}
	}
}

// ================================
// Handles
// ================================

// Automatic slope of point i (what the handle gives with z = 0)
fn float auto_slope(int i)
{
	float z = ctx.points[i].z;
	ctx.points[i].z = 0.0f;
	float m = curve_tangent(ctx.points[:ctx.point_count], i);
	ctx.points[i].z = z;
	return m;
}

// Screen position of the handle tip
fn Vec2 handle_pos(RLRectangle plot, int i)
{
	Vec2 p = ctx.points[i].transform(plot);
	float m = curve_tangent(ctx.points[:ctx.point_count], i);
	float side = i == ctx.point_count - 1 ? -1.0f : 1.0f;
	float inv = 1.0f / math::sqrt(1.0f + m * m);
	return { p.x + side * inv * HANDLE_LEN, p.y - side * m * inv * HANDLE_LEN };
}

fn int pick_point(RLRectangle plot, Vec2 m)
{
	int best = -1;
	float best_d = HIT_POINT;
	for (int i = 0; i < ctx.point_count; i++)
	{
		float d = (ctx.points[i].transform(plot) - m).length();
		if (d <= best_d) { best = i; best_d = d; }
	}
	return best;
}

fn int pick_handle(RLRectangle plot, Vec2 m)
{
	int best = -1;
	float best_d = HIT_HANDLE;
	for (int i = 0; i < ctx.point_count; i++)
	{
		if (math::abs(auto_slope(i)) < 1e-4f) continue;
		float d = (handle_pos(plot, i) - m).length();
		if (d <= best_d) { best = i; best_d = d; }
	}
	return best;
}

fn void drag_handle(RLRectangle plot, Vec2 m)
{
	int i = ctx.drag_idx;
	float ma = auto_slope(i);
	if (math::abs(ma) < 1e-4f) return;

	Vec2 p = ctx.points[i].transform(plot);
	float side = i == ctx.point_count - 1 ? -1.0f : 1.0f;

	// Target slope
	float sx = math::max((m.x - p.x) * side, 4.0f);
	float sy = -(m.y - p.y) * side;

	// curve_tangent() returns auto * (1 - z)  =>  z = 1 - slope / auto
	ctx.points[i].z = math::clamp(1.0f - (sy / sx) / ma, -1.0f, 1.0f);
}

// ================================
// Update
// ================================

fn void update(Layout l)
{
	// Grid change, applied once the spinner is no longer being edited
	int target = math::clamp(ctx.grid_value, GRID_MIN, GRID_MAX);
	if (!ctx.grid_editing && target != ctx.grid_res)
	{
		ctx.grid_res = target;
		ctx.grid_value = target;
		resnap();
	}

	Vec2 m = rl::get_mouse_position();
	bool inside = in_rect(m, l.graph);

	if (ctx.drag == Drag.NONE)
	{
		if (inside && rl::is_mouse_button_pressed(LEFT))
		{
			int h = pick_handle(l.plot, m);
			int p = pick_point(l.plot, m);
			if (h >= 0)
			{
				ctx.drag = Drag.HANDLE;
				ctx.drag_idx = h;
			}
			else if (p >= 0)
			{
				ctx.drag = Drag.POINT;
				ctx.drag_idx = p;
			}
		}
		else if (inside && rl::is_mouse_button_pressed(RIGHT))
		{
			int p = pick_point(l.plot, m);
			if (p > 0 && p < ctx.point_count - 1) { remove_point(p); }
			else if (p < 0) { add_point(to_norm(m, l.plot)); }
		}
		return;
	}

	if (!rl::is_mouse_button_down(LEFT))
	{
		ctx.drag = Drag.NONE;
		ctx.drag_idx = -1;
		return;
	}

	if (ctx.drag == Drag.POINT)  move_point(ctx.drag_idx, to_norm(m, l.plot));
	if (ctx.drag == Drag.HANDLE) drag_handle(l.plot, m);
}

// ================================
// Draw
// ================================

fn void draw_knob(Vec2 pos, float radius, RLColor border, RLColor fill)
{
	rl::draw_circle_v(pos, radius, border);
	rl::draw_circle_v(pos, radius - 2.0f, fill);
}

fn void draw_graph(RLRectangle graph, RLRectangle plot)
{
	(void)rg::panel(graph, (ZString)null);

	rl::@scissor_mode((int)graph.x, (int)graph.y, (int)graph.width, (int)graph.height)
	{
		Vec2 o = plot.origin;
		Vec2 s = plot.size;

		// Grid
		RLColor line = theme(RGGuiProperty.LINE_COLOR);
		for (int k = 0; k <= ctx.grid_res; k++)
		{
			float f = (float)k / (float)ctx.grid_res;
			RLColor c = (k == 0 || k == ctx.grid_res) ? line : line.fade(0.35f);
			rl::draw_line_v({ o.x + f * s.x, o.y }, { o.x + f * s.x, o.y + s.y }, c);
			rl::draw_line_v({ o.x, o.y + f * s.y }, { o.x + s.x, o.y + f * s.y }, c);
		}

		// Linear reference
		rl::draw_line_v({ o.x, o.y + s.y }, { o.x + s.x, o.y }, theme(RGGuiProperty.BORDER_COLOR_NORMAL).fade(0.6f));

		// Curve
		curve_draw(ctx.points[:ctx.point_count], plot, 2.5f, theme(RGGuiProperty.BORDER_COLOR_PRESSED));

		// Handles
		for (int i = 0; i < ctx.point_count; i++)
		{
			Vec2 p = ctx.points[i].transform(plot);
			Vec2 h = handle_pos(plot, i);
			Vec2 opposite = { 2.0f * p.x - h.x, 2.0f * p.y - h.y };

			bool movable = math::abs(auto_slope(i)) >= 1e-4f;
			bool active  = ctx.drag == Drag.HANDLE && ctx.drag_idx == i;

			RLColor border = theme(movable ? RGGuiProperty.BORDER_COLOR_FOCUSED : RGGuiProperty.BORDER_COLOR_DISABLED);
			RLColor fill   = theme(active  ? RGGuiProperty.BASE_COLOR_PRESSED   : (movable ? RGGuiProperty.BASE_COLOR_FOCUSED : RGGuiProperty.BASE_COLOR_DISABLED));

			rl::draw_line_v(opposite, h, border);
			draw_knob(h, 6.0f, border, fill);
		}

		// Points
		for (int i = 0; i < ctx.point_count; i++)
		{
			bool active = ctx.drag == Drag.POINT && ctx.drag_idx == i;
			draw_knob(
				ctx.points[i].transform(plot),
				7.5f,
				theme(RGGuiProperty.BORDER_COLOR_PRESSED),
				theme(active ? RGGuiProperty.BASE_COLOR_PRESSED : RGGuiProperty.BASE_COLOR_NORMAL)
			);
		}
	};
}

fn void draw_code(RLRectangle bounds) => @pool()
{
	RLFont font    = rg::get_font();
	RLColor color  = theme(RGGuiProperty.TEXT_COLOR_NORMAL);
	float size     = (float)rg::get_style(RGGuiControl.DEFAULT, RGGuiProperty.TEXT_SIZE);
	float spacing  = (float)rg::get_style(RGGuiControl.DEFAULT, RGGuiProperty.TEXT_SPACING);
	float line_h   = size + CODE_GAP;

	String[] lines = ctx.code.str_view().tsplit("\n");

	// Content size; widest line x number of lines
	float text_w = 0.0f;
	foreach (line : lines)
	{
		text_w = math::max(text_w, rl::measure_text_ex(font, line.zstr_tcopy(), size, spacing).x);
	}
	RLRectangle content = { 0.0f, 0.0f, text_w + 2.0f * CODE_PAD, (float)lines.len * line_h + 2.0f * CODE_PAD };
	RLRectangle view;

	(void)rg::scroll_panel(bounds, "GLSL", content, &ctx.code_scroll, &view);

	float x = view.origin.x + ctx.code_scroll.x + CODE_PAD;
	float y = view.origin.y + ctx.code_scroll.y + CODE_PAD;

	rl::begin_scissor_mode((int)view.origin.x, (int)view.origin.y, (int)view.size.x, (int)view.size.y);
	foreach (i, line : lines)
	{
		float row_y = y + (float)i * line_h;

		// Skip rows outside the view
		if (row_y + line_h < view.origin.y || row_y > view.origin.y + view.size.y) continue;

		rl::draw_text_ex(font, line.zstr_tcopy(), { x, row_y }, size, spacing, color);
	}
	rl::end_scissor_mode();
}

fn void draw_controls(RLRectangle c)
{
	float x = c.origin.x;
	float y = c.origin.y;
	float w = c.size.x;
	float label_w = (float)rg::get_text_width("Grid") + 10.0f;
	float half = (w - GAP) * 0.5f;

	// Grid resolution
	RLRectangle r_grid = { x + label_w, y, w - label_w, ROW_H };
	if (rg::spinner(r_grid, "Grid ", &ctx.grid_value, GRID_MIN, GRID_MAX, ctx.grid_editing) != 0)
	{
		ctx.grid_editing = !ctx.grid_editing;
	}
	y += ROW_H + GAP;

	// Generate / Preview
	RLRectangle r_generate = { x, y, half, ROW_H };
	RLRectangle r_preview  = { x + half + GAP, y, half, ROW_H };
	if (rg::button(r_generate, "Generate GLSL") != 0) generate();
	if (rg::button(r_preview, "Preview") != 0) preview_open();
	y += ROW_H + GAP;

	// Reset / Copy
	RLRectangle r_reset = { x, y, half, ROW_H };
	RLRectangle r_copy  = { x + half + GAP, y, half, ROW_H };
	if (rg::button(r_reset, "Reset") != 0) reset();

	bool empty = ctx.code.len() == 0;
	if (empty) rg::disable();
	if (rg::button(r_copy, "Copy") != 0) rl::set_clipboard_text(ctx.code.zstr_view());
	if (empty) rg::enable();
	y += ROW_H + GAP;

	// Help
	RLRectangle r_help0 = { x, y, w, ROW_H };
	RLRectangle r_help1 = { x, y + ROW_H, w, ROW_H };
	(void)rg::label(r_help0, "Left click: move point / handle");
	(void)rg::label(r_help1, "Right click: add / remove point");
}
