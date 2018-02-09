#!/usr/bin/env ruby

require 'shp'
require_relative 'crime' unless $".any? { |file| file =~ /crime\.rb/i }

module SHP

  class Shapefile
	def Shapefile.read(name)
	  f = SHP::Shapefile.open(name, "rb")
	  ret = Array.new
	  f.get_info()[:number_of_entities].times { |n|
		cell = f.read_object(n)
		cell.basefname = name
		ret.push(cell)
	  }
	  f.close()
	  ret
	end

	def Shapefile.read_hotspots(filename)
	  begin
		dbf_file = DBF.open(filename, "rb")
		return Shapefile.read(filename).find_all { |shp| shp.hotspot?(dbf_file) }
	  ensure
		dbf_file.close()
	  end
	end

	def Shapefile.total_area_hotspots(filename)
	  objs = Shapefile.read_hotspots(filename)
	  area = 0
	  objs.each { |obj|
		if obj.area < 0
		  next
		end
		area += obj.area
	  }
	  area
	end

	def Shapefile.total_area(filename)
	  objs = Shapefile.read(filename)
	  area = 0
	  objs.each { |obj|
		if obj.area < 0
		  next
		end
		area += obj.area
	  }
	  area
	end

	def Shapefile.max_cell_area(filename)
	  objs = Shapefile.read(filename)
	  max = 0
	  objs.each { |obj|
		if obj.area > max
		  max = obj.area
		end
	  }
	  max
	end

	def Shapefile.define_dbf(filename)
	  dbf_file = DBF.open(filename, "rb+")
	  dbf_file.add_field("id", DBF::FT_INTEGER, 10, 0)
	  dbf_file.add_field("hotspot", DBF::FT_INTEGER, 1, 0)
	  dbf_file.add_field("area", DBF::FT_DOUBLE, 10, 4)
	  dbf_file.close()
	end

	def Shapefile.update_dbf(filename, hotspots_filename = nil)
	  objs = Shapefile.read(filename)
	  dbf_file = DBF.open(filename, "rb+")
	  id_idx = dbf_file.get_field_index("id")
	  hotspot_idx = dbf_file.get_field_index("hotspot")
	  area_idx = dbf_file.get_field_index("area")
	  
	  objs.each { |obj|
		begin
		  dbf_file.write_integer_attribute(obj.get_shape_id, id_idx, obj.get_shape_id.to_i + 1)
		  dbf_file.write_integer_attribute(obj.get_shape_id, hotspot_idx, 0) if hotspots_filename
		  dbf_file.write_double_attribute(obj.get_shape_id, area_idx, obj.area)
		rescue
		end
	  }
	  if hotspots_filename
		hotspots = Crimes.hotspots_from_csv(hotspots_filename)
		hotspots.each { |hs|
		  hs_obj = objs.find { |obj| obj.get_x == hs.get_x and obj.get_y == hs.get_y }
		  if hs_obj.nil?
			hs_obj = objs.find { |obj| obj.get_x.collect { |x| x.truncate } == hs.get_x.collect { |x| x.truncate } and
						obj.get_y.collect { |y| y.truncate } == hs.get_y.collect { |y| y.truncate } }
		  end
		  if hs_obj.nil?
			$stderr.puts("WARNING: hotspot with vertices %s, %s not found" % [hs.get_x.join(","), hs.get_y.join(",")])
			next
		  end
		  dbf_file.write_integer_attribute(hs_obj.get_shape_id, hotspot_idx, 1)
		}
	  end
	  dbf_file.close()
	  nil
	end

	def Shapefile.create_grid(filename, wid = 250, hei = 250, x_min = 7604004.588, y_min = 651315.5578, x_max = 7701431.144, y_max = 733815.3902)
	  current_x = x_min
	  current_y = y_min
	  file = Shapefile.open(filename, "rb+")
	  while current_x < x_max
		while current_y < y_max
		  vertices_x = [ current_x, current_x, current_x + wid, current_x + wid, current_x ]
		  vertices_y = [ current_y, current_y + hei, current_y + hei, current_y, current_y ]
		  obj = Shapefile.create_simple_object(SHP::SHPT_POLYGON, vertices_x.size, vertices_x, vertices_y, nil)
		  file.write_object(-1, obj)
		  current_y += hei
		end
		current_y = y_min
		current_x += wid
	  end
	  file.close()
	end

	def Shapefile.validate(filename)
	  Shapefile.validates_by_nij_rules?(filename)
	end

	def Shapefile.validates_by_nij_rules?(filename)
	  failures = []
	  tests = %w[ validate_total_area
		  validate_forecast_area
		  validate_internal_cell_size
		  validate_polygons
	  ]
		
	  tests.each { |str|
		ret = Shapefile.send(str.to_sym, filename)
		if ret
		  failures.push(str + " (#{ret.to_s})")
		end
	  }

	  failures.each { |s| print "!! FAILED: " + s + " !!\n" }
	  failures.empty?
	end

	def Shapefile.validate_total_area_by_shpdata(filename)
	  output = `shpdata #{filename.to_s}`
	  areas = output.split.collect { |line| re = /Area = ([^\s\n]+)/.match(line); if !re then nil else re.captures.first end }.compact
	  area = 0
	  areas.each { |a| area += a.to_f }

	  total_area = area
#	  total_area = Shapefile.total_area(filename)
	  total_area_pass = total_area <= TOTAL_SQUARE_FEET + TOTAL_SQUARE_FEET_WIGGLE_ROOM and total_area >= TOTAL_SQUARE_FEET - TOTAL_SQUARE_FEET_WIGGLE_ROOM
	  if total_area_pass
		nil
	  else
		total_area
	  end
	end

	def Shapefile.validate_total_area(filename)
	  total_area = Shapefile.total_area(filename)
	  total_area_pass = total_area <= TOTAL_SQUARE_FEET + TOTAL_SQUARE_FEET_WIGGLE_ROOM and total_area >= TOTAL_SQUARE_FEET - TOTAL_SQUARE_FEET_WIGGLE_ROOM
	  if total_area_pass
		nil
	  else
		total_area
	  end
	end

	def Shapefile.validate_forecast_area(filename)
	  total_area = Shapefile.total_area_hotspots(filename)
	  max_area = Shapefile.max_cell_area(filename)

	  if total_area > MINIMUM_SQUARE_FEET * 3
		total_area
	  elsif total_area < MINIMUM_SQUARE_FEET
		total_area
	  else
		nil
	  end
	end

	def Shapefile.validate_polygons(filename)
	  cells = Shapefile.read(filename)
	  cells.any? { |c| c.get_shape_type != SHP::SHPT_POLYGON }
	end

	def Shapefile.validate_internal_cell_size(filename)
	  cells = Shapefile.read(filename)
	  internal_cells = []
	  border_cells = []
	  
	  min, max = cells.minmax_by { |c| c.area }
	  max_area = max.area

	  if max_area > 360000 or max_area < 62500
		return max_area
	  end

	  while !cells.empty?
		cell = cells.pop
		if cell.area == max_area
		  internal_cells.push(cell)
		else
		  border_cells.push(cell)
		end
	  end

	  return nil
	end

  end

  class ShapeObject
	include Enumerable
	attr_accessor :basefname

	def ShapeObject.hotspots_from_csv(filename)
	  Crimes.hotspots_from_csv(filename)
	end

	def <=>(other)
	  self.area <=> other.area
	end

	def get_attribute(attrib, dbf_file = @basefname)
	  begin
		#dbf_file.kind_of?(DBF) ? nil : dbf_file = DBF.open(dbf_file, "rb")
		dbf_file = DBF.open(dbf_file, "rb")
		idx = dbf_file.get_field_index(attrib.to_s)
		raise Exception.new("bad field: %s" % attrib.to_s)

		if dbf_file.is_attribute_null(self.get_shape_id, idx)
		  return nil
		end

		if field_type == 'N'
		  return dbf_file.read_integer_attribute(self.get_shape_id, hotspot_idx)
		elsif field_type == 'F'
		  return dbf_file.read_double_attribute(self.get_shape_id, hotspot_idx)
		else
		  return dbf_file.read_string_attribute(self.get_shape_id, hotspot_idx)
		end

	  rescue
		puts dbf_file
		puts $!.to_s, $!.backtrace
	  ensure
		dbf_file.close()
	  end
	end

	def hotspot?(filename)
	  begin
		filename.kind_of?(DBF) ? dbf_file = filename : dbf_file = DBF.open(filename, "rb")
		hotspot_idx = dbf_file.get_field_index("hotspot")
		result = dbf_file.read_integer_attribute(self.get_shape_id, hotspot_idx)
		result.to_i == 1
	  ensure
		dbf_file.close() if !filename.kind_of?(DBF)
	  end
	end

	def encloses(sorted)
	  enclosed = sorted.find_all { |x, y|
		x >= get_x_min and x <= get_x_max and y >= get_y_min and y <= get_y_max
	  }
	  enclosed
	end

	def area
	  n_points = get_x.size
	  xs = get_x
	  ys = get_y
	  j = n_points - 1
	  i = 0
	  area = 0

	  while i < n_points
		area += (xs[j] + xs[i]) * (ys[j] - ys[i])
		j = i
		i += 1
	  end
	  area / 2.0
	end
  end

end
