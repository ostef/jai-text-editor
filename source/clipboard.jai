#import "Win32";

#if OS == .WINDOWS
{
	clear_clipboard :: (using window : *Window) -> bool #must
	{
		if OpenClipboard (hwnd)
		{
			EmptyClipboard ();
			CloseClipboard ();
		
			return true;
		}

		return false;
	}

	clone_clipboard_text :: (using window : *Window, allocator : Allocator, allocator_data := null) -> string #must
	{
		text : string;

		if OpenClipboard (hwnd)
		{
			data := GetClipboardData (CF_UNICODETEXT);
			buffer := cast (*u8) GlobalLock (data);
			{
				length := WideCharToMultiByte (CP_UTF8, 0, cast (*u16) data, -1, null, 0, null, null);
				utf8 := alloc (length, allocator, allocator_data);
				WideCharToMultiByte (CP_UTF8, 0, cast (*u16) data, -1, utf8, length, null, null);

				if length
				{
					text.data  = utf8;
					text.count = length - 1;
				}

				GlobalUnlock (data);
				CloseClipboard ();
			}
		}

		return text;
	}

	set_clipboard_text :: (using window : *Window, text : string)
	{
		if !OpenClipboard (hwnd) then return;
		defer CloseClipboard ();
		EmptyClipboard ();

		length := MultiByteToWideChar (CP_UTF8, 0, cast (*s8) text.data, xx text.count, null, 0);
		utf16 := cast (*u16) alloc (length * 2 + 2, temp_allocator);
		new_length := MultiByteToWideChar (CP_UTF8, 0, cast (*s8) text.data, xx text.count, utf16, length);
		utf16[new_length] = 0;
		clipbuffer := GlobalAlloc (0, xx (new_length * 2 + 2));
		buffer := cast (*u8) GlobalLock (clipbuffer);
		memcpy (buffer, utf16, new_length * 2 + 2);
		GlobalUnlock (clipbuffer);

		SetClipboardData (CF_UNICODETEXT, clipbuffer);
	}
}
else #if OS == .LINUX
{
	clear_clipboard :: (using window : *Window) -> bool #must
	{
		// @Todo
		return false;
	}

	clone_clipboard_text :: (using window : *Window, allocator : Allocator, allocator_data := null) -> string #must
	{
		// @Todo
		return "";
	}

	set_clipboard_text :: (using window : *Window, text : string)
	{
		// @Todo
	}
}
