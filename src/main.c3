module qrvy;

import raylib6;
import rlp;

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
}

fn void quit() @RLPExport("quit")
{
}

fn void tick() @RLPExport("tick")
{
	float dt = rl::get_frame_time();

	Point[] points = {
		{ 0.0f, 0.0f, -0.5f },
		{ 0.5f, 0.2f, +0.5f },
		{ 1.0f, 1.0f, -0.5f },
	};

	rl::@drawing()
	{
		rl::clear_background(rl::DARKGRAY);

		RLRectangle screen = {
			0,
			0,
			(float)rl::get_screen_width(),
			(float)rl::get_screen_height(),
		};

		curve_draw(points, screen, 2.0f, rl::RED);

		foreach (p : points)
		{
			rl::draw_circle_v(p.xy, 8.0f, rl::BLUE);
		}
	};
}
