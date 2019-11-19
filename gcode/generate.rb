#!/usr/bin/ruby


z_feeder = 3.5 # feeder z position
x_feeder = 211.0 # feeder x position

z_target = 0.7 # target z position
z_lift = z_feeder + 10.0 # lift z position

z_slow_margin = 1 # slowdown margin around pick/place

x_count = 10
y_count = 10

cp=[]

cp[0] = [90.0, 0.0] # lower-left corner position
cp[1] = [90.0, 90.0] # lower-right corner position
cp[2] = [0.0,  0.0] # upper-left corner position
cp[3] = [0.0, 90.0] # upper-right corner position


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


bezier_intp_points = 3

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





# projective transformation
require 'matrix'


def conv1(x1, y1, x2, y2, x3, y3, x4, y4) 
	m = Matrix[
    [x1, x2, x3 ],
    [y1, y2, y3 ],
    [ 1.0,  1.0,  1.0 ]
        ]
    v = m.adjugate * Vector[x4, y4, 1.0]
    return m * Matrix[
    [v[0], 0.0, 0.0 ],
    [0.0, v[1], 0.0 ],
    [0.0, 0.0, v[2] ]
         ]
end

def calc_mat(
  x1s, y1s, x1d, y1d,
  x2s, y2s, x2d, y2d,
  x3s, y3s, x3d, y3d,
  x4s, y4s, x4d, y4d)

    s = conv1(x1s, y1s, x2s, y2s, x3s, y3s, x4s, y4s)
    d = conv1(x1d, y1d, x2d, y2d, x3d, y3d, x4d, y4d)
    return d * s.adjugate
end


def trans(mat, x, y)
	v = mat * Vector[x, y, 1.0]
	return [v[0] / v[2], 
			v[1] / v[2] ]
end

matrix = calc_mat(
	0.0,         0.0,            cp[0][0].to_f, cp[0][1].to_f,
	x_count-1.0, 0.0,            cp[1][0].to_f, cp[1][1].to_f,
	0.0, y_count-1.0,            cp[2][0].to_f, cp[2][1].to_f,
	x_count-1.0, y_count-1.0,    cp[3][0].to_f, cp[3][1].to_f)



# bezier interpolation
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
y_last = cp[0][1]
x_last = cp[0][0]
z_last = z_lift
for v in list do
	x, y = v

	target_x, target_y = trans(matrix, x.to_f, y.to_f)

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

