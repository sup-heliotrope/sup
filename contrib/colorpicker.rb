require 'ncursesw'

Ncurses.initscr
Ncurses.noecho
Ncurses.cbreak
Ncurses.start_color

Ncurses.curs_set 0
Ncurses.move 0, 0
Ncurses.clear
Ncurses.refresh
cc = Ncurses.COLORS

Ncurses::keypad(Ncurses::stdscr, 1)
Ncurses::mousemask(Ncurses::ALL_MOUSE_EVENTS | Ncurses::REPORT_MOUSE_POSITION, [])

fail "color count is #{cc}, expected 256" unless cc == 256

1.upto(255) do |c|
  Ncurses.init_pair(c, 0, c)
end

def cell y, x, c
  @map[[y,x]] = c
  Ncurses.attron(Ncurses.COLOR_PAIR(c))
  Ncurses.mvaddstr(y, x, " ")
  Ncurses.attroff(Ncurses.COLOR_PAIR(c))
end

def handle_click y, x
  c = @map[[y,x]] or return
  name = case c
  when 0...16
    c.to_s
  when 16...232
    'c' + (c-16).to_s(6).rjust(3,'0')
  when 232...256
    'g' + (c-232).to_s
  end

  Ncurses.mvaddstr 11, 0, "#{name}            "

  Ncurses.attron(Ncurses.COLOR_PAIR(c))
  10.times do |i|
    20.times do |j|
      y = 13 + i
      x = j
      Ncurses.mvaddstr(y, x, " ")
    end
  end
  Ncurses.attroff(Ncurses.COLOR_PAIR(c))
end

@map = {}
@fg = @bg = 0

begin
  16.times do |i|
    cell 0, i, i
  end

  6.times do |i|
    6.times do |j|
      6.times do |k|
        c = 16 + 6*6*i + 6*j + k
        y = 2 + j
        x = 7*i + k
        cell y, x, c
      end
    end
  end

  16.times do |i|
    c = 16 + 6*6*6 + i
    cell 9, i, c
  end

  handle_click 0, 0
  Ncurses.refresh

  while (c = Ncurses.getch)
    case c
    when 113 #q
      break
    when Ncurses::KEY_MOUSE
      mev = Ncurses::MEVENT.new
      Ncurses.getmouse(mev)
      case(mev.bstate)
      when Ncurses::BUTTON1_CLICKED
        handle_click mev.y, mev.x
      end
    end
    Ncurses.refresh
  end

ensure
  Ncurses.endwin
end
