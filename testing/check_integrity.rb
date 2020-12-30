#! /usr/bin/env ruby

require 'xdg'
require 'sqlite3'

def db_file()
  xdg = XDG::Environment.new
  data_path = xdg.data_home.to_s
  program_name = 'til'
  File.join(data_path, program_name, "notes.db")
end

def normalize_word(s)
  s.gsub(/[^[[:word:]]-]/,'').downcase
end

def normalize_spaces(s)
  s.gsub(/[[:space:]]+/, ' ')
end
    
def find_keywords(s)
  normalize_spaces(s).split.map{|w| normalize_word(w) }
end

def check_integrity()
  file = db_file()
  begin
    db = SQLite3::Database.open(file)

    h_tid = Hash.new
    db.execute('SELECT tid,tag FROM tags').each{|e|
      tid = e[0]
      tag = e[1]
      raise "ERROR: Duplicate tag #{tag}" unless h_tid[tag] == nil
      h_tid[tag] = tid
    }
    puts "Tags: OK"

    h_note_tids = Hash.new
    number_of_links1 = 0
    db.execute('SELECT nid,title,tagline,content FROM notes').each{|e|
      nid = e[0]
      title = e[1]
      tagline = e[2]
      content = e[3]
      kws = (find_keywords(title) + find_keywords(tagline)).uniq
      h_note_tids[nid] = kws.map{|kw| h_tid[kw]}
      number_of_links1 += kws.size
    }
    
    number_of_links2 = 0
    db.execute('SELECT tid,nid FROM links').each{|e|
      tid = e[0]
      nid = e[1]

      tids = h_note_tids[nid]

      i = tids.index(tid)
      raise "ERROR: Tag ID #{tid} is not found in note #{nid}" unless i != nil
      tids.delete_at(i)

      number_of_links2 += 1
    }

    puts "All tags are found in notes: OK"
    
    raise "ERROR: The number of links does not match: #{number_of_links1} <> #{number_of_links2}" unless number_of_links1 == number_of_links2

    h_note_tids.each_pair{|nid, tids|
      raise "ERROR: Stray tag IDs #{tids.inspect} in note #{nid}" unless tids.size == 0
    }

    puts "No stray tags in notes: OK"


  rescue SQLite3::Exception => e
    puts "SQLite Exception"
    puts e 
  ensure
    db.close if db
  end
end

check_integrity()
