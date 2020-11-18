Event_Type :: enum
{
	WINDOW_RESIZED;
	WINDOW_MOVED;
	
	KEY_PRESS;
	KEY_REPEAT;
	KEY_RELEASE;

	CHAR_INPUT;

	MOUSE_BUTTON_PRESS;
	MOUSE_BUTTON_RELEASE;
	MOUSE_MOTION;
	SCROLL;
}

Event :: struct
{
	type : Event_Type;
	window : *GLFWwindow;

	using data : union
	{
		key_event : struct
		{
			key : int;
			scancode : int;
			mods : int;
		};

		char_input_event : struct
		{
			codepoint : Rune;
			mods : int;
		};

		mouse_button_event : struct
		{
			button : int;
			mods : int;
			x : int;
			y : int;
			col : int;
			row : int;
		};

		mouse_motion_event : struct
		{
			x : int;
			y : int;
			col : int;
			row : int;
		};

		scroll_event : struct
		{
			x : int;
			y : int;
		};
	};
}
