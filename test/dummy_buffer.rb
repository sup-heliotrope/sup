require "sup"

module Redwood

class DummyBuffer
  attr_reader :width, :height, :dirty_count, :commit_count

  def initialize width=80, height=25
    @width = width
    @height = height
    @dirty = false
    @dirty_count = 0
    @commit_count = 0
  end

  def content_height; @height - 1; end
  def content_width; @width; end

  def mark_dirty
    @dirty = true
    @dirty_count += 1
  end

  def dirty?; @dirty; end

  def commit
    @dirty = false
    @commit_count += 1
  end

  def write(*args); end
end

end
