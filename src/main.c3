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

	rl::@drawing()
	{
		rl::clear_background(rl::DARKGRAY);
	};
}
