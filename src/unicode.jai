Rune :: u32;

RUNE_INVALID :: cast (Rune) 0xfffd;
RUNE_MAX :: cast (Rune) 0x0010ffff;
RUNE_BOM :: cast (Rune) 0xfeff;
/* @Note (stefan):
 * End of file does not exist as a unicode codepoint.
 * It is just symbolic, so we give it a value outside
 * the range of possible unicode codepoints
 */
RUNE_EOF :: RUNE_MAX + 1;

Utf8_Char :: struct
{
	n : [4]u8;
	count : u32;
}

utf8_string_length :: (str : string) -> u64, bool	// We use a signed integer so we can return -1 for invalid utf8 string
{
	length : u64;
	i := 0;
	while i < str.count
	{
		c := str[i];
		     if  c < 0x80           i += 1;
		else if (c & 0xe0) == 0xc0  i += 2;
		else if (c & 0xf0) == 0xe0  i += 3;
		else if (c & 0xf8) == 0xf0  i += 4;
		else return 0, false;

		length += 1;
	}

	return length, true;
}

utf8_string_is_valid :: inline (str : string) -> bool
{
	_, ok := utf8_string_length (str);

	return ok;
}

utf8_rune_at_byte :: (str : string, position : u64) -> Rune, u64
{
	buffer : []u8;
	buffer.data = str.data + position;
	buffer.count = str.count - xx position;
	rune, size := utf8_decode (buffer);

	return rune, size;
}

utf8_rune_at :: (str : string, position : u64) -> Rune
{
	current_position := cast (u64) 0;
	i := 0;
	
	while i < str.count
	{
		if current_position == position
		{
			buffer : []u8;
			buffer.data = str.data + i;
			buffer.count = str.count - i;
			rune, size := utf8_decode (buffer);

			return rune;
		}
		else
		{
			size := utf8_rune_size (str[i]);
			if size == 0  break;
			i += xx size;
			current_position += 1;
		}
	}

	return RUNE_INVALID;
}

utf8_char_at :: (str : string, position : u64) -> Utf8_Char
{
	current_position := cast (u64) 0;
	i := 0;

	while i < str.count
	{
		size := utf8_rune_size (str[i]);

		if size == 0  break;
		else if current_position == position
		{
			char : Utf8_Char;
			
			for j : 0..cast (s64) size - 1
			{
				char.n[j] = str[i + j];
			}

			char.count = cast (u32) size;

			return char;
		}
		
		i += xx size;
		current_position += 1;
	}

	return Utf8_Char.{};
}

utf8_decode :: (buffer : []u8) -> Rune, u64
{
	// @Note (stefan): from https://github.com/gingerBill/gb/blob/master/gb.h
	UTF8_FIRST :: u8.[
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x00-0x0F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x10-0x1F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x20-0x2F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x30-0x3F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x40-0x4F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x50-0x5F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x60-0x6F
		0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, 0xf0, // 0x70-0x7F
		0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, // 0x80-0x8F
		0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, // 0x90-0x9F
		0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, // 0xA0-0xAF
		0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, // 0xB0-0xBF
		0xf1, 0xf1, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, // 0xC0-0xCF
		0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, // 0xD0-0xDF
		0x13, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x23, 0x03, 0x03, // 0xE0-0xEF
		0x34, 0x04, 0x04, 0x04, 0x44, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, 0xf1, // 0xF0-0xFF
	];

	Utf8_Accept_Range :: struct
	{
		lo, hi : u8;
	}

	UTF8_ACCEPT_RANGES :: Utf8_Accept_Range.[
		Utf8_Accept_Range.{ 0x80, 0xbf },
		Utf8_Accept_Range.{ 0xa0, 0xbf },
		Utf8_Accept_Range.{ 0x80, 0x9f },
		Utf8_Accept_Range.{ 0x90, 0xbf },
		Utf8_Accept_Range.{ 0x80, 0x8f },
	];

	if buffer.count > 0
	{
		// @Note (stefan): Funny names... Should replace them maybe
		s0 := buffer[0];
		x  := UTF8_FIRST[s0];
		sz : u8;
		b1, b2, b3 : u8;
		range : Utf8_Accept_Range;

		if x > 0xf0
		{
			mask := (cast (Rune) x << 31) >> 31;
			
			return (cast (Rune) s0 & (~mask)) | (RUNE_INVALID & mask), 1;
		}
		else if s0 < 0x80
		{
			return s0, 1;
		}

		sz = x & 7;
		b1 = buffer[1];
		range = UTF8_ACCEPT_RANGES[x >> 4];
		if b1 < range.lo || b1 > range.hi  return RUNE_INVALID, 1;

		if sz == 2
		{
			return (cast (Rune) s0 & 0x1f) << 6 | (cast (Rune) b1 & 0x3f), 2;
		}

		b2 = buffer[2];
		if b2 < 0x80 || b2 > 0xbf  return RUNE_INVALID, 1;

		if sz == 3
		{
			return (cast (Rune) s0 & 0x1f) << 12 | (cast (Rune) b1 & 0x3f) << 6 | (cast (Rune) b2 & 0x3f), 3;
		}

		b3 = buffer[3];
		if b3 < 0x80 ||b3 > 0xbf  return RUNE_INVALID, 1;

		return (cast (Rune) s0 & 0x07) << 18 | (cast (Rune) b1 & 0x3f) << 12 | (cast (Rune) b2 & 0x3f) << 6 | (cast (Rune) b3 & 0x3f), 4;
	}

	return RUNE_INVALID, 1;
}

utf8_rune_size :: (c0 : u8) -> u64
{
	     if  c0 < 0x80           return 1;
	else if (c0 & 0xe0) == 0xc0  return 2;
	else if (c0 & 0xf0) == 0xe0  return 3;
	else if (c0 & 0xf8) == 0xf0  return 4;
	else return 0;
}

utf8_encode :: (buffer : [4]u8, rune : Rune) -> u64
{
	i := rune;
	mask := cast (u8) 0x3f;

	if i <= (1 << 7) - 1
	{
		buffer[0] = cast (u8) rune;

		return 1;
	}
	else if i <= (1 << 11) - 1
	{
		buffer[0] = 0xc0 | cast (u8) (rune >> 6);
		buffer[1] = 0x80 | (cast (u8) (rune) & mask);

		return 2;
	}
	else if i > RUNE_MAX || (i >= 0xd800 && i <= 0xdfff)
	{
		rune = RUNE_INVALID;
		buffer[0] = 0xe0 | cast (u8) (rune >> 12);
		buffer[1] = 0x80 | (cast (u8) (rune >> 6) & mask);
		buffer[2] = 0x80 | (cast (u8) (rune) & mask);
	
		return 3;
	}
	else
	{
		buffer[0] = 0xf0 |  cast (u8) (rune >> 18);
		buffer[1] = 0x80 | (cast (u8) (rune >> 12) & mask);
		buffer[2] = 0x80 | (cast (u8) (rune >> 6) & mask);
		buffer[3] = 0x80 | (cast (u8) (rune) & mask);
	
		return 4;
	}
}

is_space :: inline (rune : Rune) -> bool
{
	return (rune == #char " ") || (rune == #char "\n") || (rune == #char "\r") || (rune == #char "\t");// || (rune == #char "\v");
}

is_alpha :: inline (rune : Rune) -> bool
{
	return (rune >= #char "A") && (rune <= #char "Z") || (rune >= #char "a") && (rune <= #char "z");
}

is_digit :: inline (rune : Rune) -> bool
{
	return (rune >= #char "0") && (rune <= #char "9");
}

is_alpha_num :: inline (rune : Rune) -> bool
{
	return is_alpha (rune) || is_digit (rune) || rune == #char "_";
}

is_binary_digit :: inline (rune : Rune) -> bool
{
	return (rune == #char "0" ) || (rune == #char "1");
}

is_octal_digit :: inline (rune : Rune) -> bool
{
	return (rune >= #char "0") && (rune <= #char "7");
}

is_hex_digit :: inline (rune : Rune) -> bool
{
	return (rune >= #char "0") && (rune <= #char "9") || (rune >= #char "A") && (rune <= #char "F") || (rune >= #char "a") && (rune <= #char "f");
}
