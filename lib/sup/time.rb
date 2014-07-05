class Time

  Redwood::HookManager.register "time-to-nice-string", <<EOS
Formats time nicely as string.
Variables:
  time: The Time instance to be formatted.
  from: The Time instance providing the reference point (considered "now").
EOS

  def to_indexable_s
    sprintf "%012d", self
  end

  def nearest_hour
    if min < 30
      self
    else
      self + (60 - min) * 60
    end
  end

  def midnight # within a second
    self - (hour * 60 * 60) - (min * 60) - sec
  end

  def is_the_same_day? other
    (midnight - other.midnight).abs < 1
  end

  def is_the_day_before? other
    other.midnight - midnight <=  24 * 60 * 60 + 1
  end

  def to_nice_distance_s from=Time.now
    later_than = (self < from)
    diff = (self.to_i - from.to_i).abs.to_f
    text =
      [ ["second", 60],
        ["minute", 60],
        ["hour", 24],
        ["day", 7],
        ["week", 4.345], # heh heh
        ["month", 12],
        ["year", nil],
      ].argfind do |unit, size|
        if diff.round <= 1
          "one #{unit}"
        elsif size.nil? || diff.round < size
          "#{diff.round} #{unit}s"
        else
          diff /= size.to_f
          false
        end
      end
    if later_than
      text + " ago"
    else
      "in " + text
    end
  end

  TO_NICE_S_MAX_LEN = 9 # e.g. "Yest.10am"

  ## This is how a thread date is displayed in thread-index-mode
  def to_nice_s from=Time.now
    Redwood::HookManager.run("time-to-nice-string", :time => self, :from => from) || default_to_nice_s(from)
  end

  def default_to_nice_s from=Time.now
    if year != from.year
      strftime "%b %Y"
    elsif month != from.month
      strftime "%b %e"
    else
      if is_the_same_day? from
        format = $config[:time_mode] == "24h" ? "%k:%M" : "%l:%M%p"
        strftime(format).downcase
      elsif is_the_day_before? from
        format = $config[:time_mode] == "24h" ? "%kh" : "%l%p"
        "Yest." + nearest_hour.strftime(format).downcase
      else
        strftime "%b %e"
      end
    end
  end

  ## This is how a message date is displayed in thread-view-mode
  def to_message_nice_s from=Time.now
    format = $config[:time_mode] == "24h" ? "%B %e %Y %k:%M" : "%B %e %Y %l:%M%p"
    strftime format
  end
end

