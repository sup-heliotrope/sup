require 'highline/import'

def axe q, default=nil
  question = if default && !default.empty?
               "#{q} (enter for \"#{default}\"): "
             else
               "#{q}: "
             end
  ans = ask question
  ans.empty? ? default : ans.to_s
end

def axe_yes q, default="n"
  axe(q, default) =~ /^y|yes$/i
end

