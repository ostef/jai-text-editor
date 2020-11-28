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

insert :: inline (using buffer : *Gap_Buffer, codepoint : Rune)
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
	if cursor < gap_buffer_count (buffer)
	{
		gap += 1;
	}
}

move_cursor_forward :: inline (using buffer : *Gap_Buffer)
{
	if cursor < gap_buffer_count (buffer)
	{
		data[cursor] = data[cursor + gap];
		cursor      += 1;
	}
}

move_cursor_backward :: inline (using buffer : *Gap_Buffer)
{
	if cursor > 0
	{
		data[cursor + gap - 1] = data[cursor - 1];
		cursor -= 1;
	}
}

set_cursor :: inline (using buffer : *Gap_Buffer, new_cursor : s64)
{
	assert (new_cursor >= 0 && new_cursor <= gap_buffer_count (buffer));
	// @Cleanup (stefan): This is not the fastest implementation.
	while cursor < new_cursor  move_cursor_forward  (buffer);
	while cursor > new_cursor  move_cursor_backward (buffer);
}

gap_buffer_count :: inline (using buffer : *Gap_Buffer) -> int
{
	return data.count - gap;
}

gap_buffer_count :: inline (using buffer : Gap_Buffer) -> int
{
	return data.count - gap;
}

gap_buffer_grow :: (using buffer : *Gap_Buffer, factor : int)
{
	back    := data.count - cursor + gap;
	new_gap := gap + data.count;
	new_data     := NewArray (data.count * 2, Rune);
	memcpy (new_data.data, data.data, size_of (Rune) * cursor);
	memset (new_data.data + cursor, 1, size_of (Rune) * new_gap);		// Is this necessary ??
	memcpy (new_data.data + cursor + new_gap, data.data + cursor + gap, size_of (Rune) * back);
	
	free (data.data);
	data = new_data;
	gap  = new_gap;
}

operator [] :: inline (using buffer : Gap_Buffer, index : int) -> Rune
{
	assert (index >= 0 && index < gap_buffer_count (buffer), "Bounds check failed: index was %, should be in range [0; %]", index, gap_buffer_count (buffer) - 1);
	if index < cursor   return data[index];
	else                return data[gap + index];
}

for_expansion :: #bake_arguments for_expansion_helper (do_front = true,  do_back = true);
front         :: #bake_arguments for_expansion_helper (do_front = true,  do_back = false);
back          :: #bake_arguments for_expansion_helper (do_front = false, do_back = true);

#scope_file

for_expansion_helper :: (buffer : *Gap_Buffer, body : Code, by_pointer : bool, reverse : bool, do_front : bool, do_back : bool) #expand
{
	#assert (do_front || do_back);
	#assert (!by_pointer);

	#if reverse
	{
		#if do_back   start := gap_buffer_count (buffer) - 1;
		else          start := buffer.cursor - 1;
		#if do_front  end   := 0;
		else          end   := buffer.cursor;
	}
	else
	{
		#if do_front  start := 0;
		else          start := buffer.cursor;
		#if do_back   end   := gap_buffer_count (<<buffer) - 1;
		else          end   := buffer.cursor - 1;
	}

	for <=reverse `it_index : start..end
	{
		`it := (<<buffer)[`it_index];
		#insert (remove = #assert (false/*, "If you want to modify the contents of a gap buffer, move the cursor and do the operation."*/)) body;	// @Compiler_Bug
	}
}
