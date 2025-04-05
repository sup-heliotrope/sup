# encoding: utf-8

require "test_helper"

require "sup/util"

describe "Sup's String extension" do
  describe "#display_length" do
    let :data do
      [
        ['some words', 10,],
        ['中文', 4,],
        ['ä', 1,],
        ['😱', 2],
        #['🏳️‍🌈', 2],  # Emoji ZWJ sequence not yet supported (see PR #563)
      ]
    end

    it "calculates display length of a string" do
      data.each do |(str, length)|
        assert_equal length, str.dup.display_length
      end
    end
  end

  describe "#slice_by_display_length(len)" do
    let :data do
      [
        ['some words', 6, 'some w'],
        ['中文', 2, '中'],
        ['älpha', 3, 'älp'],
        ['😱😱', 2, '😱'],
        #['🏳️‍🌈', 2, '🏳️‍🌈'],  # Emoji ZWJ sequence not yet supported (see PR #563)
      ]
    end

    it "slices string by display length" do
      data.each do |(str, length, sliced)|
        assert_equal sliced, str.dup.slice_by_display_length(length)
      end
    end
  end

  describe "#wrap" do
    let :data do
      [
        ['some words', 6, ['some', 'words']],
        ['some words', 80, ['some words']],
        ['中文', 2, ['中', '文']],
        ['中文', 5, ['中文']],
        ['älpha', 3, ['älp', 'ha']],
        ['😱😱', 2, ['😱', '😱']],
        #['🏳️‍🌈🏳️‍🌈', 2, ['🏳️‍🌈', '🏳️‍🌈']],  # Emoji ZWJ sequence not yet supported (see PR #563)
      ]
    end

    it "wraps string by display length" do
      data.each do |(str, length, wrapped)|
        assert_equal wrapped, str.dup.wrap(length)
      end
    end
  end
end
