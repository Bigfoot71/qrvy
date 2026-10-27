module rlp;

import raylib6;

// ================================
// Main Definitions
// ================================

attrdef @RLPExport(name) = @cname("rlp_" +++ name), @export;

struct RLPApp
{
	String title;
	RLConfigFlag flags;
	int window_w;
	int window_h;
	int target_fps;
	bool audio_device;
}

extern const RLPApp APP @cname("rlp_app");
extern fn void init() @cname("rlp_init");
extern fn void tick() @cname("rlp_tick");
extern fn void quit() @cname("rlp_quit");

// ================================
// Main Function
// ================================

fn int main(String[] args) @winmain
{
	$if env::WASM:
		const RLConfigFlag WEB_SUPPORTED = VSYNC_HINT | WINDOW_RESIZABLE | WINDOW_TRANSPARENT | MSAA_4X_HINT;
		rl::set_config_flags(APP.flags & WEB_SUPPORTED);
	$else
		rl::set_config_flags(APP.flags);
	$endif

	rl::init_window(APP.window_w, APP.window_h, (ZString)APP.title);
	if (APP.audio_device) rl::init_audio_device();

	init();

	$if env::WASM:
		emscripten_set_main_loop(&tick, APP.target_fps, 1);
	$else
		rl::set_target_fps(APP.target_fps);
		while (!rl::window_should_close()) tick();
	$endif

	quit();

	rl::close_audio_device();
	rl::close_window();

	return 0;
}

// ================================
// Emscripten Stuff
// ================================

alias Em_callback_func = fn void();

extern fn void emscripten_set_main_loop(Em_callback_func func, int fps, int simulate_infinite_loop);
