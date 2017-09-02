# The `Tempfile` class is for managing temporary files.
# Every tempfile is operated as a `File`, including
# initializing, reading and writing.
#
# ```
# tempfile = Tempfile.new("foo")
# # or
# tempfile = Tempfile.open("foo") do |file|
#   file.print("foobar")
# end
#
# File.size(tempfile.path)       # => 6
# File.stat(tempfile.path).mtime # => 2015-10-20 13:11:12 UTC
# File.exists?(tempfile.path)    # => true
# File.read_lines(tempfile.path) # => ["foobar"]
# ```
#
# Files created from this class are stored in a directory that handles
# temporary files.
#
# ```
# Tempfile.new("foo").path # => "/tmp/foo.ulBCPS"
# ```
#
# Also, it is encouraged to delete a tempfile after using it, which
# ensures they are not left behind in your filesystem until garbage collected.
#
# ```
# tempfile = Tempfile.new("foo")
# tempfile.unlink
# ```
class Tempfile < IO::FileDescriptor
  DEFAULT_TEMPFILE_NAME = "tempfile"

  # Creates a `Tempfile` with the given filename.
  def initialize(name = DEFAULT_TEMPFILE_NAME)
    @path = File.join(Tempfile.dirname, name) + ".XXXXXX"
    fd = LibC.mkstemp(@path)
    if fd == -1
      raise Errno.new("mkstemp")
    end

    super(fd, blocking: true)
  end

  # Retrieves the full path of a this tempfile.
  #
  # ```
  # Tempfile.new("foo").path # => "/tmp/foo.ulBCPS"
  # ```
  getter path : String

  # Creates a file with *filename*, and yields it to the given block.
  # It is closed and returned at the end of this method call.
  #
  # ```
  # tempfile = Tempfile.open("foo") do |file|
  #   file.print("bar")
  # end
  # File.read(tempfile.path) # => "bar"
  # ```
  def self.open(name = DEFAULT_TEMPFILE_NAME)
    tempfile = Tempfile.new(name)
    begin
      yield tempfile
    ensure
      tempfile.close
    end
    tempfile
  end

  DEFAULT_POSIX_TMPDIR = "/tmp"

  # Returns the tmp dir used for tempfile.
  #
  # ```
  # Tempfile.dirname # => "/tmp"
  # ```
  def self.dirname
    unless tmpdir = ENV["TMPDIR"]?
      tmpdir = DEFAULT_POSIX_TMPDIR
    end
    File.expand_path(tmpdir)
  end

  # Deletes this tempfile.
  def delete
    File.delete(@path)
  end
end
