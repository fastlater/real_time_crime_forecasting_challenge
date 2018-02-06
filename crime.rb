#!/usr/bin/env ruby

require 'csv'
require 'time'
require_relative 'shapefile'

# 0.25 sq mi = 6969600 sq ft
MINIMUM_SQUARE_FEET = 6969600 if !defined?(MINIMUM_SQUARE_FEET)
TOTAL_SQUARE_FEET = 4.117918e+9 if !defined?(TOTAL_SQUARE_FEET)
TOTAL_SQUARE_FEET_WIGGLE_ROOM = 557568 if !defined?(TOTAL_SQUARE_FEET_WIGGLE_ROOM)
#TOTAL_SQUARE_FEET = 4117804825.3198886

class Entry
  include Enumerable
  attr_accessor :team, :timeframe, :score, :crimetype, :crimefile, :shapefile, :crimecoords

  def initialize(team, timeframe = nil, crimetype = nil, score = nil)
	@team, @timeframe, @crimetype, @score = team, timeframe, crimetype, score
  end

  def to_s
	"%25.25s (%s %s): %f" % [ @team, @crimetype, @timeframe, @score ]
  end

  def <=>(other)
	self.score <=> other.score
  end
end

module Crimes
  def burg
	ret = find_all { |crime| crime.kind_of? Burg }
	ret.extend(Crimes)
	ret
  end

  def toa
	ret = find_all { |crime| crime.kind_of? TOA }
	ret.extend(Crimes)
	ret
  end

  def sc
	ret = find_all { |crime| crime.kind_of? SC }
	ret.extend(Crimes)
	ret
  end

  def sort_by_coords!
	sort_by! { |crime| [crime.x, crime.y] }
  end

  def group_into_squares!(dim = 500)
	sort_by_coords!
	groups = Array.new
	i = 0
	j = 1
	while i < length - 1
#	  while j < length and Math.sqrt( ((self[i].x - self[j].x) ** 2) + ((self[i].y - self[j].y) ** 2) ) < dim
	  while j < length and (self[i].x - self[j].x).abs < dim and (self[i].y - self[j].y).abs < dim
		j += 1
	  end
	  groups.push(self[i...j])
	  i = j
	  j += 1
	end
	groups.extend(Crimes)
	groups
  end

  def sort!
	sort_by! { |crime| crime.date }
  end

  def weekends
	ret = find_all { |crime| crime.date.saturday? or crime.date.sunday? }
	ret.extend(Crimes)
	ret
  end

  def weekdays
	ret = find_all { |crime|
	  [ :monday?, :tuesday?, :wednesday?, :thursday?, :friday? ].any? { |sym|
		crime.send(sym)
	  }
	}
	ret.extend(Crimes)
	ret
  end

  def mean_distance
	d = 0
	begin
		each_slice(2) { |b1, b2| d += Math.sqrt(((b1.x.to_i - b2.x.to_i) ** 2) + ((b1.y.to_i - b2.y.to_i) ** 2)) }
	rescue
	end
	d / size
  end

  def Crimes.miles_to_feet(mi)
	mi / 2.788e7
  end

  def Crimes.feet_to_miles(ft)
	ft * 3.587e-8
  end

  def Crimes.sort_lines(lines, priority = [0, 4])
	sorted = lines[1..-1].sort_by { |line|
	  ary = line.split(",")
	  prio_elems = []
	  for prio in priority
		if prio == 4 or prio == -4
		  re = ary[prio].match(/(\d?\d)\/(\d?\d)\/(\d\d\d\d)/)
		  date = re ? Time.parse(re[2] + "/" + re[1] + "/" + re[3]) : nil
		  prio_elems.push(date.to_i) if date
		elsif prio == 7 or prio == -1
		  prio_elems.push ary[prio].to_i
		else
		  prio_elems.push ary[prio]
		end
	  end
	  prio_elems
	}
	sorted
  end

  def Crimes.shapeobjects_by_density(shapefile_name, crimefile_name, hotspotfile_name = nil)
	objects = SHP::Shapefile.read(shapefile_name)
	crimes = Crime.read_csv(crimefile_name)

	crimecoords = crimes.collect { |c| [c.x, c.y] }.sort
	hotspots = objects.sort_by { |obj|
		obj.encloses(crimecoords).size
	}
	
	area = 0
	winners = Array.new
	while area < MINIMUM_SQUARE_FEET
	  winners.push(hotspots.pop)
	  area += winners.last.area
	end

	if hotspotfile_name
	  File.open(hotspotfile_name, "w") { |f| winners.each { |obj| obj.get_x.each_with_index { |x, idx| f.puts("%f, %f" % [x, obj.get_y[idx]]) } } }
	end
	winners.reverse
  end

  def Crimes.hotspots_from_csv(csv_name)
	shapes = Array.new
	lines = File.readlines(csv_name)
	slices = Array.new

	i = 0
	j = 1
	while i < lines.size and j < lines.size
	  if lines[i] == lines[j]
		slices.push(lines[i..j])
		i = j + 1
		j = i + 1
	  else
		j += 1
	  end
	end

	slices.each { |ary|
	  ary = ary.collect { |line| line.chomp.split(",") }
	  x_ary = ary.collect { |elems| elems.first.to_f }
	  y_ary = ary.collect { |elems| elems.last.to_f }
	  shapes.push(SHP::Shapefile.create_simple_object(SHP::SHPT_POLYGON, x_ary.size, x_ary, y_ary, nil))
	}
	shapes
  end

  def Crimes.pai_score(hotspotsfile_name, crimefile_name, f_A = TOTAL_SQUARE_FEET, do_print = false)
#	objects = SHP::Shapefile.read(shapefile_name)
	if hotspotsfile_name.kind_of? Array
	  objects = hotspotsfile_name
	elsif hotspotsfile_name =~ /csv$/
	  objects = Crimes.hotspots_from_csv(hotspotsfile_name)
	else
	  objects = SHP::Shapefile.read(hotspotsfile_name).find_all { |shp| shp.hotspot?(hotspotsfile_name) }
	end
	crimes = Crime.read_csv(crimefile_name)

	crimecoords = crimes.collect { |c| [c.x, c.y] }
	f_n = 0
	f_N = crimecoords.size
	f_a = 0
	#f_A = TOTAL_SQUARE_FEET

	hotspots = objects.sort_by { |obj|
	  obj.encloses(crimecoords).size
	}.reverse
	
	hotspots.each { |obj|
	  f_n += obj.encloses(crimecoords).size
	  f_a += obj.area
	}
	if do_print
	  puts sprintf("     %.1f / %.1f", f_n.to_f, f_N.to_f)
	  puts ("--------------------------")
	  puts sprintf("%.1f / %.1f", f_a.to_f, f_A.to_f)
	end
	(f_n.to_f / f_N) / (f_a.to_f / f_A)
  end

  def Crimes.who_won(verbose = true)
	entries = []
	files = Dir['nij_challenge/shapefiles/*.shp']
	files.each { |filename|
	  team = File.basename(filename).slice(/[^_]+/)
	  entry = Entry.new(team)
	  entry.shapefile = filename
	  entry.timeframe = File.basename(filename).slice(/...\./)[0...-1]
	  entry.crimetype = File.basename(filename).slice(/acfs|sc|toa|burg/i).downcase
	  if entry.timeframe == "1WK"
		entry.crimefile = "NIJ2017_MAR01_MAR07-hot-"
	  elsif entry.timeframe == "2WK"
		entry.crimefile = "NIJ2017_MAR01_MAR14-hot-"
	  elsif entry.timeframe == "1MO"
		entry.crimefile = "NIJ2017_MAR01_MAR31-hot-"
	  elsif entry.timeframe == "2MO"
		entry.crimefile = "NIJ2017_MAR01_APR30-hot-"
	  elsif entry.timeframe == "3MO"
		entry.crimefile = "NIJ2017_MAR01_MAYR31-hot-"
	  end
	  entry.crimefile += entry.crimetype + ".csv"
	  entry.crimefile = File.join("nij_challenge", entry.crimefile)
	  entries.push(entry)
	  if File.exists?(entry.crimefile)
		hotspots = SHP::Shapefile.read_hotspots(filename)
		entry.score = Crimes.pai_score(hotspots, entry.crimefile, SHP::Shapefile.total_area(entry.shapefile), true)
#		puts "%s (%s %s): %f" % [ entry.team, entry.crimetype, entry.timeframe, entry.score ]
	  end
	}
	entries = entries.find_all { |e| e.score != nil and e.score.to_s != "NaN" }
	if verbose
	  %w[ acfs sc toa burg ].each { |ctype|
		%w[ 1WK 2WK 1MO 2MO 3MO ].each { |tframe|
		  puts "---- %s %s:" % [ ctype.upcase, tframe ] if verbose
		  begin
			entries.find_all { |e| e.crimetype == ctype and e.timeframe == tframe }.sort.reverse.each { |e|
			  puts "%20.20s (%s %s): %f" % [ e.team, e.crimetype, e.timeframe, e.score ] if verbose
		  }
		  rescue
			$stderr.puts $!
		  end
		  puts
		}
	  }
	end
	entries.each { |e|
	  puts sprintf("%s (%s %s) tests:", e.team, e.crimetype, e.timeframe) if verbose
	  #"%20.20s tests:" % e.team
	  fc_area = SHP::Shapefile.total_area_hotspots(e.shapefile)
	  fc_area_pass = fc_area > MINIMUM_SQUARE_FEET and fc_area < MINIMUM_SQUARE_FEET * 3

	  total_area = SHP::Shapefile.total_area(e.shapefile)
	  total_area_pass = total_area <= TOTAL_SQUARE_FEET + TOTAL_SQUARE_FEET_WIGGLE_ROOM and total_area >= TOTAL_SQUARE_FEET - TOTAL_SQUARE_FEET_WIGGLE_ROOM

	  max_cell_area = SHP::Shapefile.max_cell_area(e.shapefile)
	  max_cell_area_pass = max_cell_area <= 360000 #and max_cell_area >= 62500

	  puts " forecasted area: " + (fc_area_pass ? "PASS" : "!! FAIL !!  " + fc_area.to_s) if verbose
	  puts " total map area:  " + (total_area_pass ? "PASS" : "!! FAIL !!  " + total_area.to_s) if verbose
	  puts " map cell sizes:  " + (max_cell_area_pass ? "PASS" : "!! FAIL !!  " + max_cell_area.to_s) if verbose
	  puts if verbose
	}
	entries
  end

  def Crimes.pai_score_all_from_shapefiles(basedir = "nij_challenge")
	%w[ Burg TOA SC ACFS ].each { |crimetype|
	  avg = 0
	  n = 0
	  filenames = Dir['nij_challenge/shapefiles/*.shp']
	  filenames += Dir["nij_challenge/SUBMISSION/#{crimetype}/1WK/MURRAYMIRON_#{crimetype.upcase}_1WK.shp"]
	  best = nil
	  best_pai = 0
	  filenames.find_all { |fname| fname =~ /#{crimetype}/i }.each { |filename|
		puts "--- %s" % filename
		hotspots = SHP::Shapefile.read_hotspots(filename)#File.join(basedir, "SUBMISSION", crimetype, "1WK", "MURRAYMIRON_" + crimetype.upcase + "_1WK"))
	  #crimefilenames = Dir["#{basedir}/NIJ20*-hot-#{crimetype.downcase}.csv"]
		crimefilenames = Dir["#{basedir}/NIJ2017_MAR01*-hot-#{crimetype.downcase}.csv"]
	  #crimefilenames = Dir["#{basedir}/NIJ2017_MAR01_MAYR31-hot-#{crimetype.downcase}.csv"]
	  crimefilenames.sort_by { |fname| regex = fname.match(/NIJ(\d+)/); regex[1] }.each { |crimefile|
		pai = Crimes.pai_score(hotspots, crimefile)
		if pai > best_pai
		  best = filename
		  best_pai = pai
		end
		avg += pai
		n += 1
		puts sprintf("%s: %f", crimefile, pai)
	  }}
	  puts
	  puts "Best: %s (%f)" % [ best, best_pai ]
	  #puts sprintf("%s average: %f", crimetype, avg / n.to_f)
	  puts
	}
	nil
  end

  def Crimes.pai_score_all(hotspotfile_name = "nij_challenge/build/hotspots-")
	average = 0
	n = 0
	[ "burg.csv", "toa.csv", "sc.csv", "acfs.csv" ].each { |suffix|
	  #(Dir["nij_challenge/NIJ2017*-hot-#{suffix}"] + Dir["nij_challenge/NIJ2016*-hot-#{suffix}"] + Dir["nij_challenge/NIJ2015*-hot-#{suffix}"]).sort.each { |crimefile|
	  (Dir["nij_challenge/NIJ2017*-hot-#{suffix}"] + ["nij_challenge/NIJ2017_MAR01_MAR07-hot-sc.csv"]).sort.each { |crimefile|
		begin
		  score = Crimes.pai_score(hotspotfile_name + suffix, crimefile)
		  puts sprintf("%s: %f", crimefile, score)
		  average += score
		  n += 1
		rescue
		end
	  }
	  puts sprintf("%s average: %f", suffix, average / n) rescue()
	  average = 0
	  n = 0
	  puts
	}
	nil
  end

  def Crimes.update_all_dbf(basedir = "nij_challenge")
	[ "Burg", "SC", "TOA", "ACFS" ].each { |ctype|
	  [ "1WK", "2WK", "1MO", "2MO", "3MO" ].each { |timespan|
		dir = File.join(basedir, "SUBMISSION", ctype, timespan)
		hotspots = File.join(basedir, "build", "hotspots-250x250-#{ctype.downcase}.csv")
		puts "Updating " + File.join(dir, "MURRAYMIRON_#{ctype.upcase}_#{timespan}") + " with " + hotspots
		SHP::Shapefile.update_dbf(File.join(dir, "MURRAYMIRON_#{ctype.upcase}_#{timespan}"), hotspots)
	  }
	}
	nil
  end

  def Crimes.make_submission_dirs(basedir = "nij_challenge/SUBMISSION")
	%w[ Burg SC TOA ACFS ].each { |ctype|
  	  newdir = File.join(basedir, ctype)
	  Dir.mkdir(newdir) if !File.exists?(newdir)
	  %w[ 1WK 2WK 1MO 2MO 3MO ].each { |timespan|
		newtimedir = File.join(newdir, timespan)
		Dir.mkdir(newtimedir) if !File.exists?(newtimedir)
		system("cp -v #{basedir}/grid-250x250-fixed.prj #{basedir}/grid-250x250-fixed.shp #{basedir}/grid-250x250-fixed.shx #{basedir}/grid-250x250-fixed.dbf #{newtimedir}")
		system("rename grid-250x250-fixed MURRAYMIRON_#{ctype.upcase}_#{timespan.upcase} #{newtimedir}/*")
	  }
	}
	nil
  end
end


class Crime
  attr_accessor :x, :y, :date, :type
  def initialize(x, y, date, type)
	re = date.match(/(\d?\d)\/(\d?\d)\/(\d\d\d\d)/)
	@x, @y, @date, @type = x.to_i, y.to_i, Time.parse(re[2] + "/" + re[1] + "/" + re[3]), type
  end

  def Crime.read_csv(filename)
	Crime.parse_csv(filename)
  end

  def Crime.parse_csv(filename)
	ret = Array.new
	data = File.readlines(filename).find_all { |line| line !~ /^OTHER/ }.join
	csv = CSV.parse(data)
	csv[0..-1].each { |elem|
	  if elem[0] =~ /^STREET/
		type = SC
	  elsif elem[0] =~ /^VEHICLE/
		type = TOA
	  elsif elem[0] =~ /^BURGLARY/
		type = Burg
	  elsif elem[0] =~ /^CATEGORY/
		next
	  else
		type = CFS
	  end
	  ret.push(type.new(elem[5], elem[6], elem[4], elem[2]))
	}
	ret.extend(Crimes)
	ret
  end

  def Crime.parse_all_csv(dir = "/ntfs/Users/user/Downloads/nij_challenge")
	files = Dir["#{dir}/*-hot.csv"]
	ret = files.collect { |file| Crime.parse_csv(file) }.flatten
	ret.extend(Crimes)
	ret
  end
end

class TOA < Crime
  def to_s
	"Theft of Auto"
  end
end

class CFS < Crime
  def to_s
	"Call for Service"
  end
end

class SC < Crime
  def to_s
	"Street Crime"
  end
end

class Burg < Crime
  def to_s
	"Burglary"
  end
end


if $0 == __FILE__
  Crimes.who_won
  #Crimes.pai_score_all_from_shapefiles
end
