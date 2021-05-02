Jai_Token_Kind :: enum
{
	UNKNOWN;
	COMMENT;
	
	IDENTIFIER;
	CONTROL_KEYWORD;
	STORAGE_TYPE_KEYWORD;
	TYPE_KEYWORD;
	FUNCTION_KEYWORD;
	OTHER_KEYWORD;

	STRING_LITERAL;
	NUMBER_LITERAL;

	POLYMORPHIC_ARGUMENT;
	COMPILER_DIRECTIVE;
	INVALID_COMPILER_DIRECTIVE;
	NOTE;
	
	SYMBOL;
	EOI;
}

Jai_Token :: Token (Jai_Token_Kind);

JAI_CONTROL_KEYWORDS :: string.[ "if", "ifx", "then", "else", "case", "for", "while", "break", "continue", "return", "using", "inline" ];
JAI_STORAGE_TYPE_KEYWORDS :: string.[ "struct", "union", "enum", "enum_flags" ];
JAI_TYPE_KEYWORDS :: string.[ "void", "u8", "u16", "u32", "u64", "s8", "s16", "s32", "s64", "int", "float32", "float64", "f32", "f64", "float", "bool", "string" ];
JAI_FUNCTION_KEYWORDS :: string.[ "cast", "xx", "type_of", "type_info", "size_of", "align_of", "initializer_of" ];
JAI_OTHER_KEYWORDS :: string.[ "push_context", "context", "null", "true", "false", "it", "it_index", "no_check", "truncate", "no_dll" ];
JAI_COMPILER_DIRECTIVES :: string.[ "import", "load", "foreign", "foreign_library", "foreign_system_library", "must", "no_abc", "insert", "run", "char", "place", "through", "expand", "if", "scope_file", "scope_module", "scope_export", "assert", "bake_arguments", "complete" ];

jai_read_next_token :: (using lexer : *Lexer) -> Jai_Token #must
{
	skip_spaces (lexer);
	result : Jai_Token;
	result.kind = .UNKNOWN;
	set_token_start (lexer, *result);
	set_token_end (lexer, *result);

	if curr == end
	{
		result.kind = .EOI;
	}
	else if advance_if_matches (lexer, "//")
	{
		result.kind = .COMMENT;
		advance_to_newline (lexer);
		set_token_end (lexer, *result);
	}
	else if advance_if_matches (lexer, "/*")
	{
		result.kind = .COMMENT;
		level := 1;
		while curr < end && level != 0
		{
			if advance_if_matches (lexer, "/*")
				level += 1;
			else if advance_if_matches (lexer, "*/")
				level -= 1;
			else
				advance (lexer);
		}
		set_token_end (lexer, *result);
	}
	else if is_alpha (<<curr) || <<curr == #char "_"
	{
		while curr < end && is_alpha_num (<<curr)
			advance (lexer);

		set_token_end (lexer, *result);
		control_kw := find_first_occurence (JAI_CONTROL_KEYWORDS, result.str);
		if control_kw != -1 { result.kind = .CONTROL_KEYWORD; return result; }

		storage_type_kw := find_first_occurence (JAI_STORAGE_TYPE_KEYWORDS, result.str);
		if storage_type_kw != -1 { result.kind = .STORAGE_TYPE_KEYWORD; return result; }
		
		type_kw := find_first_occurence (JAI_TYPE_KEYWORDS, result.str);
		if type_kw != -1 { result.kind = .TYPE_KEYWORD; return result; }
		
		function_kw := find_first_occurence (JAI_FUNCTION_KEYWORDS, result.str);
		if function_kw != -1 { result.kind = .FUNCTION_KEYWORD; return result; }

		other_kw := find_first_occurence (JAI_OTHER_KEYWORDS, result.str);
		if other_kw != -1 { result.kind = .OTHER_KEYWORD; return result; }
	
		result.kind = .IDENTIFIER;
	}
	else if is_digit (<<curr)
	{
		while curr < end && is_digit (<<curr)
			advance (lexer);

		result.kind = .NUMBER_LITERAL;
		set_token_end (lexer, *result);
	}
	else if <<curr == #char "\""
	{
		advance (lexer);
		while curr < end && <<curr != #char "\""
		{
			if <<curr == #char "\\" then advance (lexer);
			advance (lexer);
		}
		advance (lexer);

		set_token_end (lexer, *result);
		result.kind = .STRING_LITERAL;
	}
	else if <<curr == #char "#"
	{
		advance (lexer);
		skip_spaces (lexer);	// #                   import is a valid compiler directive, same for newlines between the '#' and the keyword
		while curr < end && is_alpha_num (<<curr)
			advance (lexer);
		
		set_token_end (lexer, *result);
		compiler_directive := find_first_occurence (JAI_COMPILER_DIRECTIVES, skip_spaces (advance (result.str)));
		if compiler_directive == -1 then result.kind = .INVALID_COMPILER_DIRECTIVE;
		else result.kind = .COMPILER_DIRECTIVE;
	}
	else if <<curr == #char "$"
	{
		advance (lexer);
		while curr < end && !is_space (<<curr)
			advance (lexer);

		set_token_end (lexer, *result);
		result.kind = .POLYMORPHIC_ARGUMENT;
	}
	else if <<curr == #char "@"
	{
		advance (lexer);
		while curr < end && !is_space (<<curr)
			advance (lexer);

		set_token_end (lexer, *result);
		result.kind = .NOTE;
	}
	else
	{
		advance (lexer);
		set_token_end (lexer, *result);
		result.kind = .SYMBOL;
	}

	return result;
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
	token.str.data  = token.start;
	token.str.count = token.end - token.start;
}
