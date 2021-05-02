Lexer :: struct
{
	filename : string;
	start, end, curr : *u8;
	l0, c0 : s64;
}

Token :: struct (Kind : Type)
{
	kind   : Kind;
	str    : string;
	start, end : *u8;
	l0, c0 : s64;
	l1, c1 : s64;
}

Language :: enum
{
	NONE;
	JAI;
}

make_lexer :: (contents : string) -> Lexer #must
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

make_lexer :: (filename : string, contents : string) -> Lexer #must
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
	if end - curr < str.count then return false;
	for i : 0..str.count - 1
	{
		if curr[i] != str[i] then return false;
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
	str : string = ---;
	str.data  = curr;
	str.count = end - curr;
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
	str : string = ---;
	str.data  = curr;
	str.count = end - curr;
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
	str : string = ---;
	str.data  = curr;
	str.count = end - curr;
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
	str : string = ---;
	str.data  = curr;
	str.count = end - curr;
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

	result : string = ---;
	result.data  = str_start;
	result.count = str_end - str_start;

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

	result : string = ---;
	result.data  = str_start;
	result.count = str_end - str_start;

	return result, true;
}
