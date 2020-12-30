#! /usr/bin/env ruby

require 'xdg'
require 'sqlite3'
require 'colorize'
require 'tempfile'
require 'json'

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

def edit_entry(start_title='', start_tags='', start_text='')
  file = Tempfile.new('til')
  file.puts(start_title)
  file.puts(start_tags)
  file.print(start_text)
  file.close

  system("vim #{file.path}")
  arr = File.read(file.path).split("\n")
  title = arr[0] || ''
  tags = arr[1] || ''
  text = (arr[2..-1] || '').join("\n") 

  file.unlink
  [title, tags, text]
end

def add_keywords(db, nid, title, tagline)
  def find_keywords(s)
    normalize_spaces(s).split.map{|w| normalize_word(w) }
  end

  kws = (find_keywords(title) + find_keywords(tagline)).uniq

  kws.each{|w|
    res = db.get_first_row('SELECT tid,counter FROM tags WHERE tag = ?', w)
    if res == nil
      db.execute('INSERT INTO tags VALUES (NULL,?,?)', w, 0)
      tid = db.last_insert_row_id
      counter = 0
      res = [tid, counter]
    end
    tid = res[0].to_i
    counter = res[1].to_i
    db.execute('INSERT INTO links (tid, nid) VALUES (?,?)', tid, nid)
    db.execute('UPDATE tags SET counter = ? WHERE tid = ?', counter + 1, tid)
  }
end

def remove_keywords(db, nid)
  arr = db.execute('SELECT tid, COUNT(tid) FROM links WHERE nid = ? GROUP BY tid', nid)
  arr.each{|row|
    tid = row[0]
    count = row[1]
    
    counter = db.get_first_row('SELECT counter FROM tags WHERE tid = ?', tid)[0].to_i
    new_counter = counter - count

    if new_counter > 0
      db.execute('UPDATE tags SET counter = ? WHERE tid = ?', new_counter, tid)
    else
      db.execute('DELETE FROM tags WHERE tid = ?', tid)
    end
    db.execute('DELETE FROM links WHERE nid = ?', nid)
  }
end

def add(db, title, tagline, content)
  db.execute('INSERT INTO notes VALUES (NULL,?,?,?)', title, tagline, content)
  nid = db.last_insert_row_id
  add_keywords(db, nid, title, tagline)
end

def update(db, nid, title, tagline, content)
  remove_keywords(db, nid)
  db.execute('UPDATE notes SET title = ?, tagline = ?, content = ? WHERE nid = ?', title, tagline, content, nid)
  add_keywords(db, nid, title, tagline)
end

def init()
  file = db_file()
  
  dirname = File.dirname(file)
  if not File.exist?(dirname)
    Dir.mkdir(dirname)
  end

  begin
    db = SQLite3::Database.open(file)
    db.execute "CREATE TABLE IF NOT EXISTS notes(nid INTEGER PRIMARY KEY, title TEXT, tagline TEXT, content TEXT)"
    db.execute "CREATE TABLE IF NOT EXISTS tags(tid INTEGER PRIMARY KEY, tag TEXT, counter INTEGER)"
    db.execute "CREATE TABLE IF NOT EXISTS links(tid INTEGER, nid INTEGER)"

  rescue SQLite3::Exception => e
    puts "SQLite Exception"
    puts e 
  ensure
    db.close if db
  end
end

def transaction(procedure)
  begin
    file = db_file()
    db = SQLite3::Database.open(file)
    db.transaction

    procedure.call(db)

    db.commit
  rescue SQLite3::Exception => e
    puts "SQLite Exception"
    puts e
    db.rollback
  ensure
    db.close if db
  end
end
    
def vacuum()
  file = db_file()
  db = SQLite3::Database.open(file)
  db.execute('VACUUM')
  db.close if db
end

def run()

  case ARGV[0]
  when 'add'
    title,tags,text = edit_entry()
    transaction(Proc.new{|db| 
      add(db, title, tags, text) 
    })
  when 'edit'
    nid = ARGV[1].to_i
    
    db = SQLite3::Database.open(db_file())
    row = db.get_first_row('SELECT title,tagline,content FROM notes WHERE nid = ?', nid)
    db.close if db 

    if row != nil
      title = row[0]
      tagline = row[1]
      content = row[2] 
      new_title,new_tagline,new_content = edit_entry(title,tagline,content)
      transaction(Proc.new{|db| 
        update(db, nid, new_title, new_tagline, new_content) 
      })
      vacuum()
    end
  when 'del'
    nid = ARGV[1].to_i
    
    db = SQLite3::Database.open(db_file())
    row = db.get_first_row('SELECT title,tagline,content FROM notes WHERE nid = ?', nid)
    db.close if db 

    if row != nil
      transaction(Proc.new{|db| 
        remove_keywords(db, nid)
        db.execute('DELETE FROM notes WHERE nid = ?', nid)
      })
      vacuum()
    end
  
  when 'find' 
    tags = ARGV[1..-1].map{|t| normalize_word(t) }.uniq
    db = SQLite3::Database.open(db_file())
    
    tag_records = Array.new

    tags.map{|t| 
      res = db.get_first_row('SELECT tid,counter FROM tags WHERE tag = ?', t)
      if res != nil
        tid = res[0]
        counter = res[1]
        nids = Array.new
        db.execute('SELECT nid FROM links WHERE tid = ?', tid).each{|entry|
          nids << entry[0]
        }
        tag_records << {:tid => res[0], :tag => t, :counter => counter, :nids => nids}
      end
    }

    note_score = Hash.new(0)
    note_tagcount = Hash.new(0)
    tag_records.each{|r|
      c = r[:counter]
      score = 1.0/c
      r[:nids].each{|nid|
        note_score[nid] += score
        note_tagcount[nid] += 1
      }
    }
    max_tagcount = note_tagcount.values.max

    notes = Array.new
    note_tagcount.each_pair{|nid, tagcount| 
      if tagcount == max_tagcount
        res = db.get_first_row('SELECT title,tagline,content FROM notes WHERE nid = ?', nid)
        if res != nil
          title = res[0]
          tagline = res[1]
          content = res[2]
          score = note_score[nid]
          notes << {:nid => nid, :title => title, :tagline => tagline, :content => content, :score => score}
        end
      end
    }
    db.close if db

    notes.sort_by!{|note| -note[:score]}

    notes.each{|note|
      print "#{note[:nid]}. ".colorize(:blue)
      print "#{note[:title].strip} ".colorize(:green)
      print "(#{note[:tagline].strip})\n".colorize(:light_black)
      print "#{note[:content]}"
      puts ""
      puts ""
    }

  when 'clear'
    transaction(Proc.new{|db| 
      db.execute "DELETE FROM notes"
      db.execute "DELETE FROM tags"
      db.execute "DELETE FROM links"
    })
    vacuum()
  
  when 'export'
    def f(s)
      s.gsub(/"/, '\"').gsub(/\n/, '\n')
    end
    transaction(Proc.new{|db|
      print "["
      first = true
      db.execute("SELECT nid,title,tagline,content FROM notes").each{|rec|
        if first 
          first = false
        else
          puts ","
        end
        #print "{\"title\":\"#{f(rec[1])}\", \"tagline\":\"#{f(rec[2])}\", \"content\":\"#{f(rec[3])}\"}"
        print JSON.pretty_generate({'title' => rec[1], "tagline" => rec[2], "content" => rec[3]})
      }
      puts "]"
    })
  
  when 'import'
    filename = ARGV[1]
    data = []

    if filename != nil 
      if File.exist?(filename)
        file = File.open(filename)
        data = JSON.load(file)
        file.close
      end
    else
      data = JSON.load(STDIN)
    end

    transaction(Proc.new{|db| 
      data.each{|entry|
        add(db, entry['title'], entry['tagline'], entry['content']) 
      }
    })
  end

end
  
init()
run()
