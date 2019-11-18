#!/usr/bin/ruby


z_feeder = 3.5 # feeder z position
x_feeder = 211.0 # feeder x position

z_target = 0.7 # target z position
z_lift = z_feeder + 10.0 # lift z position

z_slow_margin = 1 # slowdown margin around pick/place

x_count = 48
y_count = 54

x_pitch = 3.85
y_pitch = 3.83075

x_start = -15.00 # x_start position
y_start = -11.00 # y_start position
x_end = x_start + (x_count-1) * x_pitch # x_end position
y_end = y_start + (y_count-1) * y_pitch # y_end position


confirm_count = 8

$round_prec = 4

class Numeric
	def r
		return self.round($round_prec)
	end
end


unloaded_move_speed = 150 * 60 # unloaded move speed mm/minute
loaded_move_speed   =  60 * 60 # loaded move speed mm/minute
slow_move_speed   =  1 * 60 # slow move speed mm/minute around pick/place


gcode_pump_on = "M400\nM106\nG4 S1"
gcode_pump_off = "M400\nM107\nG4 S1"
gcode_feed = "M400\nM42 P211 S255\nG4 P50\nM42 P211 S0"


bezier_intp_points = 100

gcode_start ="
M80 ; power on
G4 S3 ; wait for a while
M18 S0 ; disable motor timeout
G21 ; millimeter unit
G90 ; absolute position
G1 F#{unloaded_move_speed.r}
#{gcode_pump_off} 
"


gcode_end ="
G1 F#{unloaded_move_speed.r}
G1 Z#{z_lift.r}
"

print gcode_start

if ARGV[0] == "-b" then

	# repeat visiting four corners of the target area
	print "G1 F#{unloaded_move_speed.r}\n"
	10 .times do
		print "G1 Z#{(z_target + z_slow_margin).r}\n"
		print "G1 X#{x_start.r} Y#{y_start.r}\n"
		print "G1 Z#{z_target.r}\n"
		print "M0\n"
		print "G1 Z#{(z_target + z_slow_margin).r}\n"
		print "G1 X#{x_end.r} Y#{y_start.r}\n"
		print "G1 Z#{z_target.r}\n"
		print "M0\n"
		print "G1 Z#{(z_target + z_slow_margin).r}\n"
		print "G1 X#{x_end.r} Y#{y_end.r}\n"
		print "G1 Z#{z_target.r}\n"
		print "M0\n"
		print "G1 Z#{(z_target + z_slow_margin).r}\n"
		print "G1 X#{x_start.r} Y#{y_end.r}\n"
		print "G1 Z#{z_target.r}\n"
		print "M0\n"
		print "\n"
	end
	exit 0
end





# initialize the list
list = []



if 1 then
	# array generate
	# push coordinates to the list
	for y in 0 .. (y_count-1) do
		for x in 0 .. (x_count-1) do
			list.push([x, y])
		end
	end

	$cx = (x_count-1)/2.0
	$cy = (y_count-1)/2.0
	list.sort! { |a, b| -(  (a[0]-$cx)**2 + (a[1]-$cy)**2 <=>  (b[0]-$cx)**2 + (b[1]-$cy)**2 )}

end

def intp3d(a, b, t)
	rt = 1 - t
	[rt * a[0] + t * b[0],  rt * a[1] + t * b[1],  rt * a[2] + t * b[2] ]
end

# generate array of [x,y,z] according to bezier curve parameter p1, p2, p3, p4, number_of_interporation
def bezier3d(p1, p2, p3, p4, n)
	ar = []
	ar.push(p1)
	n.times do |i|
		t = (i+1).to_f / (n+1)
		p5 = intp3d(p1, p2, t)
		p6 = intp3d(p2, p3, t)
		p7 = intp3d(p3, p4, t)
		p8 = intp3d(p5, p6, t)
		p9 = intp3d(p6, p7, t)
		pz = intp3d(p8, p9, t)
		ar.push(pz)
	end
	ar.push(p4)
end



# iterate list
cnt = 0
y_last = y_start
x_last = x_start
z_last = z_lift
for v in list do
	x, y = v

	target_x = x_pitch * x + x_start
	target_y = y_pitch * y + y_start

	print "M117 x #{x}, y #{y} @ #{target_x.r}, #{target_y.r}\n"

	# move to feeder position
	print "G0 F#{unloaded_move_speed.r}\n"
	print ";-- bezier start\n"
	bezier3d(
		[x_last, y_last, z_last],
		[x_last, y_last, z_lift],
		[x_feeder, y_last, z_lift],
		[x_feeder, y_last, z_feeder + z_slow_margin],
		bezier_intp_points).each do |i|
		x, y, z = i
		print "G0 X#{x.r} Y#{y.r} Z#{z.r}\n"
	end
	print ";-- bezier end\n"

	print "G0 X#{x_feeder.r}\n"

	# lift down to feeder
	print "G0 Z#{(z_feeder + z_slow_margin).r}\n"
	print "M0\n" if cnt < confirm_count
	print "G1 F#{slow_move_speed.r}\n"
	print "G1 Z#{z_feeder.r}\n"

	# pump on
	print "#{gcode_pump_on}\n"

	# lift up
	print "G1 Z#{(z_feeder + z_slow_margin).r}\n"
	print "G1 F#{loaded_move_speed.r}\n"

	# feed one step
	print "#{gcode_feed}\n"

	# go to target position
	print ";-- bezier start\n"
	bezier3d(
		[x_feeder, y_last, z_feeder + z_slow_margin],
		[x_feeder, y_last, z_lift],
		[target_x, target_y, z_lift],
		[target_x, target_y, z_target + z_slow_margin],
		bezier_intp_points).each do |i|
		x, y, z = i
		print "G1 X#{x.r} Y#{y.r} Z#{z.r}\n"
	end
	y_last = target_y
	print ";-- bezier end\n"

	# lift down
	print "M0\n" if cnt < confirm_count
	print "G1 F#{slow_move_speed.r}\n"
	print "G1 Z#{z_target.r}\n"

	# pump off
	print "#{gcode_pump_off}\n"

	# lift up
	print "G1 F#{unloaded_move_speed.r}\n"
	print "G1 Z#{(z_target + z_slow_margin).r}\n"
	z_last = z_target + z_slow_margin
	x_last = target_x


	cnt = cnt + 1
end

print gcode_end

