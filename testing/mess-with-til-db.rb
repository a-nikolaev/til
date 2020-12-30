#! /usr/bin/env ruby

require 'xdg'
require 'json'

def db_file()
  xdg = XDG::Environment.new
  data_path = xdg.data_home.to_s
  program_name = 'til'
  File.join(data_path, program_name, "notes.db")
end

def rnd_char()
  (('!'..'~').to_a).sample
end

def rnd_letter()
  (('a'..'z').to_a + ('A'..'Z').to_a).sample
end

def rnd_word()
  s = ''
  (0 + rand(3)).times{
    s << rnd_char()
  }
  (1 + rand(3)).times{
    s << rnd_letter()
  }
  (0 + rand(3)).times{
    s << rnd_char()
  }
  s
end

def rnd_text()
  s = rnd_word()
  (1 + rand(8)).times{
    s += ' ' + rnd_word()
  }
  s
end

def rnd_entry()
  {'title' => rnd_text(), 'tagline' => rnd_text(), 'content' => rnd_text()}
end

def check_integrity()
end

def run_test()
  
  `../til.rb clear`

  n = 100

  n.times{|i|
    puts "insert #{i}"
    f = File.open('temp.json', 'w+')
    f.write('[' + JSON.generate(rnd_entry) + ']')
    f.close
    system('../til.rb import temp.json')
  }
  
  10.times{|i|
    puts "edit #{i}"
    j = rand(n+1)
    system("../til.rb edit #{j}")
  }

  (n/3).times{|i|
    puts "delete #{i}"
    j = rand(n+1)
    system("../til.rb del #{j}")
  }

end

run_test()
