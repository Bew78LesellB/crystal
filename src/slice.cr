require "c/string"

# A `Slice` is a `Pointer` with an associated size.
#
# While a pointer is unsafe because no bound checks are performed when reading from and writing to it,
# reading from and writing to a slice involve bound checks.
# In this way, a slice is a safe alternative to `Pointer`.
#
# A Slice can be created as read-only: trying to write to it
# will raise. For example the slice of bytes returned by
# `String#to_slice` is read-only.
struct Slice(T)
  include Indexable(T)

  # Create a new `Slice` with the given *args*. The type of the
  # slice will be the union of the type of the given *args*.
  #
  # The slice is allocated on the heap.
  #
  # ```
  # slice = Slice[1, 'a']
  # slice[0]    # => 1
  # slice[1]    # => 'a'
  # slice.class # => Slice(Char | Int32)
  # ```
  #
  # If `T` is a `Number` then this is equivalent to
  # `Number.slice` (numbers will be coerced to the type `T`)
  #
  # See also: `Number.slice`.
  macro [](*args, read_only = false)
    # TODO: there should be a better way to check this, probably
    # asking if @type was instantiated or if T is defined
    {% if @type.name != "Slice(T)" && T < Number %}
      {{T}}.slice({{*args}}, read_only: {{read_only}})
    {% else %}
      %ptr = Pointer(typeof({{*args}})).malloc({{args.size}})
      {% for arg, i in args %}
        %ptr[{{i}}] = {{arg}}
      {% end %}
      Slice.new(%ptr, {{args.size}}, read_only: {{read_only}})
    {% end %}
  end

  # Returns the size of this slice.
  #
  # ```
  # Slice(UInt8).new(3).size # => 3
  # ```
  getter size : Int32

  # Returns `true` if this slice cannot be written to.
  getter? read_only : Bool

  # Creates a slice to the given *pointer*, bounded by the given *size*. This
  # method does not allocate heap memory.
  #
  # ```
  # ptr = Pointer.malloc(9) { |i| ('a'.ord + i).to_u8 }
  #
  # slice = Slice.new(ptr, 3)
  # slice.size # => 3
  # slice      # => Bytes[97, 98, 99]
  #
  # String.new(slice) # => "abc"
  # ```
  def initialize(@pointer : Pointer(T), size : Int, *, @read_only = false)
    @size = size.to_i32
  end

  # Allocates `size * sizeof(T)` bytes of heap memory initialized to zero
  # and returns a slice pointing to that memory.
  #
  # The memory is allocated by the `GC`, so when there are
  # no pointers to this memory, it will be automatically freed.
  #
  # Only works for primitive integers and floats (`UInt8`, `Int32`, `Float64`, etc.)
  #
  # ```
  # slice = Slice(UInt8).new(3)
  # slice # => Bytes[0, 0, 0]
  # ```
  def self.new(size : Int, *, read_only = false)
    {% unless T <= Int::Primitive || T <= Float::Primitive %}
      {% raise "Can only use primitive integers and floats with Slice.new(size), not #{T}" %}
    {% end %}

    pointer = Pointer(T).malloc(size)
    new(pointer, size, read_only: read_only)
  end

  # Allocates `size * sizeof(T)` bytes of heap memory initialized to the value
  # returned by the block (which is invoked once with each index in the range `0...size`)
  # and returns a slice pointing to that memory.
  #
  # The memory is allocated by the `GC`, so when there are
  # no pointers to this memory, it will be automatically freed.
  #
  # ```
  # slice = Slice.new(3) { |i| i + 10 }
  # slice # => Slice[10, 11, 12]
  # ```
  def self.new(size : Int, *, read_only = false)
    pointer = Pointer.malloc(size) { |i| yield i }
    new(pointer, size, read_only: read_only)
  end

  # Allocates `size * sizeof(T)` bytes of heap memory initialized to *value*
  # and returns a slice pointing to that memory.
  #
  # The memory is allocated by the `GC`, so when there are
  # no pointers to this memory, it will be automatically freed.
  #
  # ```
  # slice = Slice.new(3, 10)
  # slice # => Slice[10, 10, 10]
  # ```
  def self.new(size : Int, value : T, *, read_only = false)
    new(size, read_only: read_only) { value }
  end

  # Returns a copy of this slice.
  # This method allocates memory for the slice copy.
  def clone
    copy = self.class.new(size)
    copy.copy_from(self)
    copy
  end

  # Creates an empty slice.
  #
  # ```
  # slice = Slice(UInt8).empty
  # slice.size # => 0
  # ```
  def self.empty
    new(Pointer(T).null, 0)
  end

  # Returns a new slice that is *offset* elements apart from this slice.
  #
  # ```
  # slice = Slice.new(5) { |i| i + 10 }
  # slice # => Slice[10, 11, 12, 13, 14]
  #
  # slice2 = slice + 2
  # slice2 # => Slice[12, 13, 14]
  # ```
  def +(offset : Int)
    unless 0 <= offset <= size
      raise IndexError.new
    end

    Slice.new(@pointer + offset, @size - offset, read_only: @read_only)
  end

  # Sets the given value at the given *index*.
  #
  # Negative indices can be used to start counting from the end of the slice.
  # Raises `IndexError` if trying to set an element outside the slice's range.
  #
  # ```
  # slice = Slice.new(5) { |i| i + 10 }
  # slice[0] = 20
  # slice[-1] = 30
  # slice # => Slice[20, 11, 12, 13, 30]
  #
  # slice[10] = 1 # raises IndexError
  # ```
  @[AlwaysInline]
  def []=(index : Int, value : T)
    check_writable

    index += size if index < 0
    unless 0 <= index < size
      raise IndexError.new
    end

    @pointer[index] = value
  end

  # Returns a new slice that starts at *start* elements from this slice's start,
  # and of *count* size.
  #
  # Raises `IndexError` if the new slice falls outside this slice.
  #
  # ```
  # slice = Slice.new(5) { |i| i + 10 }
  # slice # => Slice[10, 11, 12, 13, 14]
  #
  # slice2 = slice[1, 3]
  # slice2 # => Slice[11, 12, 13]
  # ```
  def [](start, count)
    unless 0 <= start <= @size
      raise IndexError.new
    end

    unless 0 <= count <= @size - start
      raise IndexError.new
    end

    Slice.new(@pointer + start, count, read_only: @read_only)
  end

  @[AlwaysInline]
  def unsafe_at(index : Int)
    @pointer[index]
  end

  # Reverses in-place all the elements of `self`.
  def reverse!
    check_writable

    return self if size <= 1

    p = @pointer
    q = @pointer + size - 1

    while p < q
      p.value, q.value = q.value, p.value
      p += 1
      q -= 1
    end

    self
  end

  def pointer(size)
    unless 0 <= size <= @size
      raise IndexError.new
    end

    @pointer
  end

  def shuffle!(random = Random::DEFAULT)
    check_writable

    @pointer.shuffle!(size, random)
  end

  # Invokes the given block for each element of `self`, replacing the element
  # with the value returned by the block. Returns `self`.
  #
  # ```
  # slice = Slice[1, 2, 3]
  # slice.map! { |x| x * x }
  # slice # => Slice[1, 4, 9]
  # ```
  def map!
    check_writable

    @pointer.map!(size) { |e| yield e }
    self
  end

  # Returns a new slice where elements are mapped by the given block.
  #
  # ```
  # slice = Slice[1, 2.5, "a"]
  # slice.map &.to_s # => Slice["1", "2.5", "a"]
  # ```
  def map(*, read_only = false, &block : T -> U) forall U
    Slice.new(size, read_only: read_only) { |i| yield @pointer[i] }
  end

  # Like `map!`, but the block gets passed both the element and its index.
  def map_with_index!(&block : (T, Int32) -> T)
    check_writable

    @pointer.map_with_index!(size) { |e, i| yield e, i }
    self
  end

  # Like `map`, but the block gets passed both the element and its index.
  def map_with_index(*, read_only = false, &block : (T, Int32) -> U) forall U
    Slice.new(size, read_only: read_only) { |i| yield @pointer[i], i }
  end

  def copy_from(source : Pointer(T), count)
    check_writable

    pointer(count).copy_from(source, count)
  end

  def copy_to(target : Pointer(T), count)
    pointer(count).copy_to(target, count)
  end

  # Copies the contents of this slice into *target*.
  #
  # Raises `IndexError` if the desination slice cannot fit the data being transferred
  # e.g. dest.size < self.size.
  #
  # ```
  # src = Slice['a', 'a', 'a']
  # dst = Slice['b', 'b', 'b', 'b', 'b']
  # src.copy_to dst
  # dst             # => Slice['a', 'a', 'a', 'b', 'b']
  # dst.copy_to src # raises IndexError
  # ```
  def copy_to(target : self)
    target.check_writable

    @pointer.copy_to(target.pointer(size), size)
  end

  # Copies the contents of *source* into this slice.
  #
  # Raises `IndexError` if the desination slice cannot fit the data being transferred.
  @[AlwaysInline]
  def copy_from(source : self)
    source.copy_to(self)
  end

  def move_from(source : Pointer(T), count)
    check_writable

    pointer(count).move_from(source, count)
  end

  def move_to(target : Pointer(T), count)
    pointer(count).move_to(target, count)
  end

  # Moves the contents of this slice into *target*. *target* and `self` may
  # overlap; the copy is always done in a non-destructive manner.
  #
  # Raises `IndexError` if the desination slice cannot fit the data being transferred
  # e.g. `dest.size < self.size`.
  #
  # ```
  # src = Slice['a', 'a', 'a']
  # dst = Slice['b', 'b', 'b', 'b', 'b']
  # src.move_to dst
  # dst             # => Slice['a', 'a', 'a', 'b', 'b']
  # dst.move_to src # raises IndexError
  # ```
  #
  # See also: `Pointer#move_to`.
  def move_to(target : self)
    target.check_writable

    @pointer.move_to(target.pointer(size), size)
  end

  # Moves the contents of *source* into this slice. *source* and `self` may
  # overlap; the copy is always done in a non-destructive manner.
  #
  # Raises `IndexError` if the desination slice cannot fit the data being transferred.
  @[AlwaysInline]
  def move_from(source : self)
    source.move_to(self)
  end

  def inspect(io)
    to_s(io)
  end

  # Returns a hexstring representation of this slice, assuming it's
  # a `Slice(UInt8)`.
  #
  # ```
  # slice = UInt8.slice(97, 62, 63, 8, 255)
  # slice.hexstring # => "613e3f08ff"
  # ```
  def hexstring
    self.as(Slice(UInt8))

    str_size = size * 2
    String.new(str_size) do |buffer|
      hexstring(buffer)
      {str_size, str_size}
    end
  end

  # :nodoc:
  def hexstring(buffer)
    self.as(Slice(UInt8))

    offset = 0
    each do |v|
      buffer[offset] = to_hex(v >> 4)
      buffer[offset + 1] = to_hex(v & 0x0f)
      offset += 2
    end

    nil
  end

  # Returns a hexdump of this slice, assuming it's a `Slice(UInt8)`.
  # This method is specially useful for debugging binary data and
  # incoming/outgoing data in protocols.
  #
  # ```
  # slice = UInt8.slice(97, 62, 63, 8, 255)
  # slice.hexdump # => "00000000  61 3e 3f 08 ff                                    a>?.."
  # ```
  def hexdump
    self.as(Slice(UInt8))

    return "" if empty?

    full_lines, leftover = size.divmod(16)
    if leftover == 0
      str_size = full_lines * 77 - 1
      lines = full_lines
    else
      str_size = (full_lines + 1) * 77 - (16 - leftover) - 1
      lines = full_lines + 1
    end

    String.new(str_size) do |buf|
      index_offset = 0
      hex_offset = 10
      ascii_offset = 60

      # Ensure we don't write outside the buffer:
      # slower, but safer (speed is not very important when hexdump is used)
      buffer = Slice.new(buf, str_size)

      each_with_index do |v, i|
        if i % 16 == 0
          0.upto(7) do |j|
            buffer[index_offset + 7 - j] = to_hex((i >> (4 * j)) & 0xf)
          end
          buffer[index_offset + 8] = ' '.ord.to_u8
          buffer[index_offset + 9] = ' '.ord.to_u8
          index_offset += 77
        end

        buffer[hex_offset] = to_hex(v >> 4)
        buffer[hex_offset + 1] = to_hex(v & 0x0f)
        buffer[hex_offset + 2] = ' '.ord.to_u8
        hex_offset += 3

        buffer[ascii_offset] = (v > 31 && v < 127) ? v : '.'.ord.to_u8
        ascii_offset += 1

        if i % 8 == 7
          buffer[hex_offset] = ' '.ord.to_u8
          hex_offset += 1
        end

        if i % 16 == 15 && ascii_offset < str_size
          buffer[ascii_offset] = '\n'.ord.to_u8
          hex_offset += 27
          ascii_offset += 61
        end
      end

      while hex_offset % 77 < 60
        buffer[hex_offset] = ' '.ord.to_u8
        hex_offset += 1
      end

      {str_size, str_size}
    end
  end

  private def to_hex(c)
    ((c < 10 ? 48_u8 : 87_u8) + c)
  end

  def bytesize
    sizeof(T) * size
  end

  def ==(other : self)
    return false if bytesize != other.bytesize
    return LibC.memcmp(to_unsafe.as(Void*), other.to_unsafe.as(Void*), bytesize) == 0
  end

  def to_slice
    self
  end

  def to_s(io)
    if T == UInt8
      io << "Bytes["
      # Inspect using to_s because we know this is a UInt8.
      join ", ", io, &.to_s(io)
      io << ']'
    else
      io << "Slice["
      join ", ", io, &.inspect(io)
      io << ']'
    end
  end

  def pretty_print(pp) : Nil
    prefix = T == UInt8 ? "Bytes[" : "Slice["
    pp.list(prefix, self, "]")
  end

  def to_a
    Array(T).build(@size) do |pointer|
      pointer.copy_from(@pointer, @size)
      @size
    end
  end

  # Returns this slice's pointer.
  #
  # ```
  # slice = Slice.new(3, 10)
  # slice.to_unsafe[0] # => 10
  # ```
  def to_unsafe : Pointer(T)
    @pointer
  end

  # :nodoc:
  def index(object, offset : Int = 0)
    # Optimize for the case of looking for a byte in a byte slice
    if T.is_a?(UInt8.class) &&
       (object.is_a?(UInt8) || (object.is_a?(Int) && 0 <= object < 256))
      return fast_index(object, offset)
    end

    super
  end

  # :nodoc:
  def fast_index(object, offset)
    offset += size if offset < 0
    if 0 <= offset < size
      result = LibC.memchr(to_unsafe + offset, object, size - offset)
      if result
        return (result - to_unsafe.as(Void*)).to_i32
      end
    end

    nil
  end

  # See `Object#hash(hasher)`
  def hash(hasher)
    {% if T == UInt8 %}
      hasher.bytes(self)
    {% else %}
      super hasher
    {% end %}
  end

  protected def check_writable
    raise "Can't write to read-only Slice" if @read_only
  end
end

# A convenient alias for the most common slice type,
# a slice of bytes, used for example in `IO#read` and `IO#write`.
#alias Bytes = Slice(UInt8)
#----------------------------------------------------------

struct Bytes
  # I was about to copy the 550 lines of Slice
  # that a bit too much ^^

  # Returns the result of interpreting leading characters in this string as an
  # integer base *base* (between 2 and 36).
  #
  # If there is not a valid number at the start of this string,
  # or if the resulting integer doesn't fit an `Int32`, an `ArgumentError` is raised.
  #
  # Options:
  # * **whitespace**: if `true`, leading and trailing whitespaces are allowed
  # * **underscore**: if `true`, underscores in numbers are allowed
  # * **prefix**: if `true`, the prefixes `"0x"`, `"0"` and `"0b"` override the base
  # * **strict**: if `true`, extraneous characters past the end of the number are disallowed
  #
  # ```
  # "12345".to_i             # => 12345
  # "0a".to_i                # raises ArgumentError
  # "hello".to_i             # raises ArgumentError
  # "0a".to_i(16)            # => 10
  # "1100101".to_i(2)        # => 101
  # "1100101".to_i(8)        # => 294977
  # "1100101".to_i(10)       # => 1100101
  # "1100101".to_i(base: 16) # => 17826049
  #
  # "12_345".to_i                   # raises ArgumentError
  # "12_345".to_i(underscore: true) # => 12345
  #
  # "  12345  ".to_i                    # => 12345
  # "  12345  ".to_i(whitespace: false) # raises ArgumentError
  #
  # "0x123abc".to_i               # raises ArgumentError
  # "0x123abc".to_i(prefix: true) # => 1194684
  #
  # "99 red balloons".to_i                # raises ArgumentError
  # "99 red balloons".to_i(strict: false) # => 99
  # ```
  def to_i(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true)
    to_i32(base, whitespace, underscore, prefix, strict)
  end

  # Same as `#to_i`, but returns `nil` if there is not a valid number at the start
  # of this string, or if the resulting integer doesn't fit an `Int32`.
  #
  # ```
  # "12345".to_i?             # => 12345
  # "99 red balloons".to_i?   # => nil
  # "0a".to_i?(strict: false) # => 0
  # "hello".to_i?             # => nil
  # ```
  def to_i?(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true)
    to_i32?(base, whitespace, underscore, prefix, strict)
  end

  # Same as `#to_i`, but returns the block's value if there is not a valid number at the start
  # of this string, or if the resulting integer doesn't fit an `Int32`.
  #
  # ```
  # "12345".to_i { 0 } # => 12345
  # "hello".to_i { 0 } # => 0
  # ```
  def to_i(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true, &block)
    to_i32(base, whitespace, underscore, prefix, strict) { yield }
  end

  # Same as `#to_i` but returns an `Int8`.
  def to_i8(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : Int8
    to_i8(base, whitespace, underscore, prefix, strict) { raise ArgumentError.new("Invalid Int8: #{self}") }
  end

  # Same as `#to_i` but returns an `Int8` or `nil`.
  def to_i8?(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : Int8?
    to_i8(base, whitespace, underscore, prefix, strict) { nil }
  end

  # Same as `#to_i` but returns an `Int8` or the block's value.
  def to_i8(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true, &block)
    gen_to_ i8, 127, 128
  end

  # Same as `#to_i` but returns an `UInt8`.
  def to_u8(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : UInt8
    to_u8(base, whitespace, underscore, prefix, strict) { raise ArgumentError.new("Invalid UInt8: #{self}") }
  end

  # Same as `#to_i` but returns an `UInt8` or `nil`.
  def to_u8?(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : UInt8?
    to_u8(base, whitespace, underscore, prefix, strict) { nil }
  end

  # Same as `#to_i` but returns an `UInt8` or the block's value.
  def to_u8(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true, &block)
    gen_to_ u8, 255
  end

  # Same as `#to_i` but returns an `Int16`.
  def to_i16(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : Int16
    to_i16(base, whitespace, underscore, prefix, strict) { raise ArgumentError.new("Invalid Int16: #{self}") }
  end

  # Same as `#to_i` but returns an `Int16` or `nil`.
  def to_i16?(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : Int16?
    to_i16(base, whitespace, underscore, prefix, strict) { nil }
  end

  # Same as `#to_i` but returns an `Int16` or the block's value.
  def to_i16(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true, &block)
    gen_to_ i16, 32767, 32768
  end

  # Same as `#to_i` but returns an `UInt16`.
  def to_u16(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : UInt16
    to_u16(base, whitespace, underscore, prefix, strict) { raise ArgumentError.new("Invalid UInt16: #{self}") }
  end

  # Same as `#to_i` but returns an `UInt16` or `nil`.
  def to_u16?(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : UInt16?
    to_u16(base, whitespace, underscore, prefix, strict) { nil }
  end

  # Same as `#to_i` but returns an `UInt16` or the block's value.
  def to_u16(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true, &block)
    gen_to_ u16, 65535
  end

  # Same as `#to_i`.
  def to_i32(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : Int32
    to_i32(base, whitespace, underscore, prefix, strict) { raise ArgumentError.new("Invalid Int32: #{self}") }
  end

  # Same as `#to_i`.
  def to_i32?(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : Int32?
    to_i32(base, whitespace, underscore, prefix, strict) { nil }
  end

  # Same as `#to_i`.
  def to_i32(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true, &block)
    gen_to_ i32, 2147483647, 2147483648
  end

  # Same as `#to_i` but returns an `UInt32`.
  def to_u32(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : UInt32
    to_u32(base, whitespace, underscore, prefix, strict) { raise ArgumentError.new("Invalid UInt32: #{self}") }
  end

  # Same as `#to_i` but returns an `UInt32` or `nil`.
  def to_u32?(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : UInt32?
    to_u32(base, whitespace, underscore, prefix, strict) { nil }
  end

  # Same as `#to_i` but returns an `UInt32` or the block's value.
  def to_u32(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true, &block)
    gen_to_ u32, 4294967295
  end

  # Same as `#to_i` but returns an `Int64`.
  def to_i64(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : Int64
    to_i64(base, whitespace, underscore, prefix, strict) { raise ArgumentError.new("Invalid Int64: #{self}") }
  end

  # Same as `#to_i` but returns an `Int64` or `nil`.
  def to_i64?(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : Int64?
    to_i64(base, whitespace, underscore, prefix, strict) { nil }
  end

  # Same as `#to_i` but returns an `Int64` or the block's value.
  def to_i64(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true, &block)
    gen_to_ i64, 9223372036854775807, 9223372036854775808
  end

  # Same as `#to_i` but returns an `UInt64`.
  def to_u64(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : UInt64
    to_u64(base, whitespace, underscore, prefix, strict) { raise ArgumentError.new("Invalid UInt64: #{self}") }
  end

  # Same as `#to_i` but returns an `UInt64` or `nil`.
  def to_u64?(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true) : UInt64?
    to_u64(base, whitespace, underscore, prefix, strict) { nil }
  end

  # Same as `#to_i` but returns an `UInt64` or the block's value.
  def to_u64(base : Int = 10, whitespace = true, underscore = false, prefix = false, strict = true, &block)
    gen_to_ u64
  end

  # :nodoc:
  CHAR_TO_DIGIT = begin
    table = StaticArray(Int8, 256).new(-1_i8)
    10_i8.times do |i|
      table.to_unsafe[48 + i] = i
    end
    26_i8.times do |i|
      table.to_unsafe[65 + i] = i + 10
      table.to_unsafe[97 + i] = i + 10
    end
    table
  end

  # :nodoc:
  CHAR_TO_DIGIT62 = begin
    table = CHAR_TO_DIGIT.clone
    26_i8.times do |i|
      table.to_unsafe[65 + i] = i + 36
    end
    table
  end

  # :nodoc:
  record ToU64Info,
    value : UInt64,
    negative : Bool,
    invalid : Bool

  private macro gen_to_(method, max_positive = nil, max_negative = nil)
    info = to_u64_info(base, whitespace, underscore, prefix, strict)
    return yield if info.invalid

    if info.negative
      {% if max_negative %}
        return yield if info.value > {{max_negative}}
        -info.value.to_{{method}}
      {% else %}
        return yield
      {% end %}
    else
      {% if max_positive %}
        return yield if info.value > {{max_positive}}
      {% end %}
      info.value.to_{{method}}
    end
  end

  private def to_u64_info(base, whitespace, underscore, prefix, strict)
    raise ArgumentError.new("Invalid base #{base}") unless 2 <= base <= 36 || base == 62

    ptr = to_unsafe

    # Skip leading whitespace
    if whitespace
      while ptr.value.unsafe_chr.ascii_whitespace?
        ptr += 1
      end
    end

    negative = false
    found_digit = false
    mul_overflow = ~0_u64 / base

    # Check + and -
    case ptr.value.unsafe_chr
    when '+'
      ptr += 1
    when '-'
      negative = true
      ptr += 1
    end

    # Check leading zero
    if ptr.value.unsafe_chr == '0'
      ptr += 1

      if prefix
        case ptr.value.unsafe_chr
        when 'b'
          base = 2
          ptr += 1
        when 'x'
          base = 16
          ptr += 1
        else
          base = 8
        end
        found_digit = false
      else
        found_digit = true
      end
    end

    value = 0_u64
    last_is_underscore = true
    invalid = false

    digits = (base == 62 ? CHAR_TO_DIGIT62 : CHAR_TO_DIGIT).to_unsafe
    while ptr.value != 0
      if ptr.value.unsafe_chr == '_' && underscore
        break if last_is_underscore
        last_is_underscore = true
        ptr += 1
        next
      end

      last_is_underscore = false
      digit = digits[ptr.value]
      if digit == -1 || digit >= base
        break
      end

      if value > mul_overflow
        invalid = true
        break
      end

      value *= base

      old = value
      value += digit
      if value < old
        invalid = true
        break
      end

      found_digit = true
      ptr += 1
    end

    if found_digit
      unless ptr.value == 0
        if whitespace
          while ptr.value.unsafe_chr.ascii_whitespace?
            ptr += 1
          end
        end

        if strict && ptr.value != 0
          invalid = true
        end
      end
    else
      invalid = true
    end

    ToU64Info.new value, negative, invalid
  end

  # Returns the result of interpreting characters in this string as a floating point number (`Float64`).
  # This method raises an exception if the string is not a valid float representation.
  #
  # Options:
  # * **whitespace**: if `true`, leading and trailing whitespaces are allowed
  # * **strict**: if `true`, extraneous characters past the end of the number are disallowed
  #
  # ```
  # "123.45e1".to_f                # => 1234.5
  # "45.67 degrees".to_f           # raises ArgumentError
  # "thx1138".to_f(strict: false)  # raises ArgumentError
  # " 1.2".to_f(whitespace: false) # raises ArgumentError
  # "1.2foo".to_f(strict: false)   # => 1.2
  # ```
  def to_f(whitespace = true, strict = true)
    to_f64(whitespace: whitespace, strict: strict)
  end

  # Returns the result of interpreting characters in this string as a floating point number (`Float64`).
  # This method returns `nil` if the string is not a valid float representation.
  #
  # Options:
  # * **whitespace**: if `true`, leading and trailing whitespaces are allowed
  # * **strict**: if `true`, extraneous characters past the end of the number are disallowed
  #
  # ```
  # "123.45e1".to_f?                # => 1234.5
  # "45.67 degrees".to_f?           # => nil
  # "thx1138".to_f?                 # => nil
  # " 1.2".to_f?(whitespace: false) # => nil
  # "1.2foo".to_f?(strict: false)   # => 1.2
  # ```
  def to_f?(whitespace = true, strict = true)
    to_f64?(whitespace: whitespace, strict: strict)
  end

  # Same as `#to_f` but returns a Float32.
  def to_f32(whitespace = true, strict = true)
    to_f32?(whitespace: whitespace, strict: strict) || raise ArgumentError.new("Invalid Float32: #{self}")
  end

  # Same as `#to_f?` but returns a Float32.
  def to_f32?(whitespace = true, strict = true)
    to_f_impl(whitespace: whitespace, strict: strict) do
      v = LibC.strtof self, out endptr
      {v, endptr}
    end
  end

  # Same as `#to_f`.
  def to_f64(whitespace = true, strict = true)
    to_f64?(whitespace: whitespace, strict: strict) || raise ArgumentError.new("Invalid Float64: #{self}")
  end

  # Same as `#to_f?`.
  def to_f64?(whitespace = true, strict = true)
    to_f_impl(whitespace: whitespace, strict: strict) do
      v = LibC.strtod self, out endptr
      {v, endptr}
    end
  end

  private def to_f_impl(whitespace = true, strict = true)
    return unless whitespace || '0'.ord <= self[0] <= '9'.ord || self[0] == '-'.ord || self[0] == '+'.ord

    v, endptr = yield
    string_end = to_unsafe + bytesize

    # blank string
    return if endptr == to_unsafe

    if strict
      if whitespace
        while endptr < string_end && endptr.value.chr.ascii_whitespace?
          endptr += 1
        end
      end
      # reached the end of the string
      v if endptr == string_end
    else
      ptr = to_unsafe
      if whitespace
        while ptr < string_end && ptr.value.chr.ascii_whitespace?
          ptr += 1
        end
      end
      # consumed some bytes
      v if endptr > ptr
    end
  end
end
