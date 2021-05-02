Lexer :: struct
{
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
	result.start    = contents.data;
	result.end      = contents.data + contents.count;
	result.curr     = result.start;
	result.l0 = 1;
	result.c0 = 1;

	return result;
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
