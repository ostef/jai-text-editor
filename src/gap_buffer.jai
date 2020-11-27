Gap_Buffer :: struct
{
	data   : []Rune;
	cursor : s64;
	gap    : s64;
}

make_gap_buffer :: inline (capacity : int) -> Gap_Buffer
{
	using result : Gap_Buffer;
	data     = NewArray (capacity, Rune);
	gap      = capacity;

	return result;
}

destroy_gap_buffer :: inline (using buffer : *Gap_Buffer)
{
	free (data.data);
	data.count = 0;
	cursor     = 0;
	gap        = 0;
}

insert_to_gap_buffer :: inline (using buffer : *Gap_Buffer, codepoint : Rune)
{
	if gap == 0  gap_buffer_grow (buffer, 2);
	data[cursor] = codepoint;
	cursor      += 1;
	gap         -= 1;
}

backspace :: inline (using buffer : *Gap_Buffer)
{
	if cursor > 0
	{
		cursor -= 1;
		gap    += 1;
	}
}

delete :: inline (using buffer : *Gap_Buffer)
{
	if data.count > cursor + gap
	{
		gap += 1;
	}
}

move_cursor_forward :: inline (using buffer : *Gap_Buffer)
{
	back := data.count - cursor + gap;
	if back > 0
	{
		data[cursor] = data[cursor + gap];
		cursor      += 1;
	}
}

move_cursor_backward :: inline (using buffer : *Gap_Buffer)
{
	if cursor > 0
	{
		data[cursor + gap] = data[cursor];
		cursor            -= 1;
	}
}

set_cursor :: (using buffer : *Gap_Buffer, new_cursor : s64)
{
	assert (new_cursor >= 0 && new_cursor <= data.count - gap);
	// @Cleanup (stefan): Obviously this is not the fastest implementation AT ALL.
	while cursor < new_cursor  move_cursor_forward  (buffer);
	while cursor > new_cursor  move_cursor_backward (buffer);
}

gap_buffer_grow :: (using buffer : *Gap_Buffer, factor : int)
{
	back    := data.count - cursor;
	new_gap := data.count;
	new_data     := NewArray (data.count * 2, Rune);
	memcpy (new_data.data, data.data, size_of (Rune) * cursor);
	//memset (new_data.data + cursor, 0, size_of (Rune) * new_gap);		// Is this necessary ??
	memcpy (new_data.data + cursor + new_gap, data.data + cursor + gap, size_of (Rune) * back);
	
	free (data.data);
	data = new_data;
	gap  = new_gap;
}

for_expansion :: (using buffer : *Gap_Buffer, body : Code, by_pointer : bool, reverse : bool) #expand
{
	#assert (!reverse);		// @Incomplete

	`it_index := 0;
	should_break := false;
	while it_index < cursor && !should_break
	{
		#if by_pointer
		{
			`it := *data[it_index];
		}
		else
		{
			`it := data[it_index];
		}
		
		#insert body;	// @Incomplete (stefan): We should handle break and remove.
	}

	it_index += gap;
	while it_index < data.count && !should_break
	{
		#if by_pointer
		{
			`it := *data[it_index];
		}
		else
		{
			`it := data[it_index];
		}
		
		#insert body;
	}
}

front :: (using buffer : Gap_Buffer, body : Code, by_pointer : bool, reverse : bool) #expand
{
	#assert (!reverse);		// @Incomplete

	for `it_index : 0..cursor - 1
	{
		#if by_pointer
		{
			`it := *data[it_index];
		}
		else
		{
			`it := data[it_index];
		}
		
		#insert body;
	}
}

back :: (using buffer : Gap_Buffer, body : Code, by_pointer : bool, reverse : bool) #expand
{
	#assert (!reverse);		// @Incomplete

	for `it_index : cursor + gap..data.count - 1
	{
		#if by_pointer
		{
			`it := *data[it_index];
		}
		else
		{
			`it := data[it_index];
		}
		
		#insert body;
	}
}
