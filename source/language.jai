Lexer :: struct
{
	filename : string;
	start, end, curr : *u32;
	l0, c0 : s64;
}

Token :: struct (Kind : Type)
{
	kind   : Kind;
	utf32  : []u32;
	start, end : *u32;
	l0, c0 : s64;
	l1, c1 : s64;
}

set_token_start :: inline (using lexer : *Lexer, token : *Jai_Token)
{
	token.start = curr;
	token.l0    = l0;
	token.c0    = c0;
}

set_token_end :: inline (using lexer : *Lexer, token : *Jai_Token)
{
	token.end = curr;
	token.l1  = l0;
	token.c1  = c0;
	token.utf32.data  = token.start;
	token.utf32.count = token.end - token.start;
}

Language :: enum
{
	NONE;
	JAI;
}

make_lexer :: (contents : []u32) -> Lexer #must
{
	result : Lexer = ---;
	result.filename = "";
	result.start    = contents.data;
	result.end      = contents.data + contents.count;
	result.curr     = result.start;
	result.l0 = 1;
	result.c0 = 1;

	return result;
}

make_lexer :: (filename : string, contents : []u32) -> Lexer #must
{
	result : Lexer = ---;
	result.filename = filename;
	result.start    = contents.data;
	result.end      = contents.data + contents.count;
	result.curr     = result.start;
	result.l0 = 1;
	result.c0 = 1;

	return result;
}

report_error :: (using lexer : Lexer, header : string, fmt : string, args : ..Any) -> bool
{
	str := fstring (temp_allocator, "'%' (%, %): %", filename, l0, c0, fmt);

	return log_error (header, str, ..args);
}

advance :: (using lexer : *Lexer, count := 1)
{
	i := 0;
	while curr < end && i < count
	{
		if <<curr == #char "\n"
		{
			l0 += 1;
			c0 = 0;
		}

		curr += 1;
		c0   += 1;
		i    += 1;
	}
}

advance_to_newline :: (using lexer : *Lexer)
{
	while curr < end && <<curr != #char "\n"
		advance (lexer);
}

advance_until_matches :: (using lexer : *Lexer, str : string) -> bool
{
	ok := false;
	while curr < end && !ok
	{
		ok = matches (lexer, str);
		if !ok then advance (lexer);
	}

	return ok;
}

advance_until_space :: (using lexer : *Lexer) -> bool
{
	ok := false;
	while curr < end && !ok
	{
		ok = is_space (<<curr);
		if !ok then advance (lexer);
	}

	return ok;
}

advance_if_matches :: (lexer : *Lexer, str : string) -> bool #must
{
	if matches (lexer, str)
	{
		advance (lexer, str.count);
		
		return true;
	}
	
	return false;
}

matches :: (using lexer : *Lexer, str : string) -> bool #must
{
	utf32 := utf8_string_to_runes (str, temp_allocator);

	if end - curr < utf32.count then return false;
	for i : 0..utf32.count - 1
	{
		if curr[i] != utf32[i] then return false;
	}

	return true;
}

skip_spaces :: (using lexer : *Lexer) -> int
{
	i := 0;
	while curr < end && is_space (<<curr)
	{
		advance (lexer);
		i += 1;
	}

	return i;
}

read_s64 :: (using lexer : *Lexer) -> value : s64, ok : bool
{
	skip_spaces (lexer);
	utf32 : []u32 = ---;
	utf32.data  = curr;
	utf32.count = end - curr;
	str := utf8_runes_to_string (utf32, temp_allocator);
	value, ok, remainder := string_to_s64 (str);

	if ok
	{
		advance (lexer, remainder.data - curr);

		return value, true;
	}

	return 0, false;
}

read_u64 :: (using lexer : *Lexer) -> value : u64, ok : bool
{
	skip_spaces (lexer);
	utf32 : []u32 = ---;
	utf32.data  = curr;
	utf32.count = end - curr;
	str := utf8_runes_to_string (utf32, temp_allocator);
	value, ok, remainder := string_to_u64 (str);
	
	if ok
	{
		advance (lexer, remainder.data - curr);

		return value, true;
	}

	return 0, false;
}

read_f64 :: (using lexer : *Lexer) -> value : f64, ok : bool
{
	skip_spaces (lexer);
	utf32 : []u32 = ---;
	utf32.data  = curr;
	utf32.count = end - curr;
	str := utf8_runes_to_string (utf32, temp_allocator);
	value, ok, remainder := string_to_f64 (str);
	
	if ok
	{
		advance (lexer, remainder.data - curr);

		return value, true;
	}

	return 0, false;
}

read_bool :: (using lexer : *Lexer) -> value : bool, ok : bool
{
	skip_spaces (lexer);
	utf32 : []u32 = ---;
	utf32.data  = curr;
	utf32.count = end - curr;
	str := utf8_runes_to_string (utf32, temp_allocator);
	value, ok, remainder := string_to_bool (str);
	
	if ok
	{
		advance (lexer, remainder.data - curr);

		return value, true;
	}

	return false, false;
}

read_identifier :: (using lexer : *Lexer) -> ident : string, ok : bool
{
	skip_spaces (lexer);
	if !is_alpha (<<curr) && <<curr != #char "_" then return "", false;
	str_start := curr;
	while curr < end && is_alpha_num (<<curr)
		advance (lexer);
	str_end := curr;

	utf32 : []u32 = ---;
	utf32.data  = str_start;
	utf32.count = str_end - str_start;
	result := utf8_runes_to_string (utf32, temp_allocator);

	return result, true;
}

read_string :: read_maybe_quoted_string;
read_maybe_quoted_string :: (using lexer : *Lexer) -> value : string, ok : bool
{
	skip_spaces (lexer);
	quoted := <<curr == #char "\"";
	if quoted then advance (lexer);
	str_start := curr;
	if quoted then advance_until_matches (lexer, "\"");
	else advance_until_space (lexer);
	str_end := curr;
	if quoted && curr == end then return "", false;
	if quoted then advance (lexer);

	utf32 : []u32 = ---;
	utf32.data  = str_start;
	utf32.count = str_end - str_start;
	result := utf8_runes_to_string (utf32, temp_allocator);

	return result, true;
}
