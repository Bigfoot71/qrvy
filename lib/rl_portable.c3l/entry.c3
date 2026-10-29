module rlp;

import raylib6;

// ================================
// Public: RLP Definitions
// ================================

attrdef @RLPExport(name) = @cname("rlp_" +++ name), @export;

struct RLPApp
{
	String          title;
	RLConfigFlag    flags;
	int             window_w;
	int             window_h;
	int             target_fps;
	RLKeyboardKey   exit_key;
	RLTraceLogLevel log_level;
	bool            audio_device;
}

extern const RLPApp APP @cname("rlp_app");

extern fn void rlp_init(String[] args) @local;
extern fn void rlp_tick(float dt)      @local;
extern fn void rlp_quit()              @local;

// ================================
// Public: RLP Functions
// ================================

fn void request_quit()
{
	ctx.quit_requested = true;
}

// ================================
// Local: Main Functions
// ================================

fn int main(String[] args) @winmain
{
	$if env::WASM:
	{
		main_init(args);
		emscripten_set_main_loop(&main_tick, 0, 1);
	}
	$else
	{
		main_init(args);
		defer main_quit();
		rl::set_target_fps(APP.target_fps);
		while (!rl::window_should_close() && !ctx.quit_requested) main_tick();
	}
	$endif

	return 0;
}

fn void main_init(String[] args) @local
{
	$if env::WASM:
		const RLConfigFlag WEB_SUPPORTED = VSYNC_HINT | WINDOW_RESIZABLE | WINDOW_TRANSPARENT | MSAA_4X_HINT;
		rl::set_config_flags(APP.flags & WEB_SUPPORTED);
	$else
		rl::set_config_flags(APP.flags);
	$endif

	rl::set_trace_log_level(APP.log_level);

	rl::init_window(APP.window_w, APP.window_h, APP.title.zstr_tcopy());
	if (APP.audio_device) rl::init_audio_device();
	rl::set_exit_key(APP.exit_key);

	$if !env::WASM:
		main_setup_working_dir();
	$endif

	rlp_init(args);
}

fn void main_quit() @local
{
	rlp_quit();

	if (rl::is_audio_device_ready())
	{
		rl::close_audio_device();
	}
	rl::close_window();
}

fn void main_tick() @local
{
	rl::@drawing()
	{
		rlp_tick(rl::get_frame_time());
	};

	$if env::WASM:
		if (ctx.quit_requested)
		{
			main_quit();
			emscripten_cancel_main_loop();
		}
	$endif
}

fn void main_setup_working_dir() @local @feat(!WASM) => @pool()
{
	String app_dir = rl::get_application_directory().str_view();
	DString prefix = dstring::temp();

	for (int i = 0; i < 4; i++)
	{
		String root = string::tformat("%s/%s", app_dir, prefix.str_view());
		if (rl::directory_exists(string::tformat("%sassets", root).zstr_tcopy()))
		{
			rl::change_directory(root.zstr_tcopy());
			return;
		}
		prefix.append("../");
	}
}

// ================================
// Local: Main Context
// ================================

struct Context @local
{
	bool quit_requested;
}

Context ctx @local;

// ================================
// Local: Emscripten Declarations
// ================================

alias Em_callback_func @local = fn void();

extern fn void emscripten_set_main_loop(Em_callback_func func, int fps, int simulate_infinite_loop) @local;
extern fn void emscripten_cancel_main_loop() @local;
