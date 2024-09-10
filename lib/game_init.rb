# Put the one-time game setup code that comes before `loop do` here.

MAX_DELTA_FI = 15 # degrees
MAX_DELTA_POWER = 1 # strenght of thrust
MAX_X = 6999 # meters
MAX_Y = 2999 # meters
MINUMIM_LANDING_WIDTH = 1000 # m

MAX_SAFE_HORIZONTAL_CRUISE_SPEED = 50 # ms
MAX_SAFE_VERTICAL_CRUISE_SPEED = 8 # ms
MAX_SAFE_HORIZONTAL_SPEED = 19 # m/s
MAX_SAFE_VERTICAL_SPEED = 39 # m/s # 40 in rules, but it's too unsafe

RIGHT_DIRECTIONS = [1, 2, 7, 8].to_set.freeze
LEFT_DIRECTIONS = [3, 4, 5, 6].to_set.freeze
LANDING_DIRECTIONS = [6, 7].to_set.freeze

class Controller
  attr_reader :surface, :points, :landing_line, :previous_lander_location
  attr_reader :move_graph

  def initialize(surface)
    @surface = surface

    @surface.each_cons(2) do |a, b|
      next unless (b.x - a.x >= MINUMIM_LANDING_WIDTH) && a.y == b.y

      @landing_line = Segment.new(a, b)
      debug "Landing detected at #{@landing_line}"
    end

    @points = [*@surface].to_set

    # @move_graph = Graph.new

    # (-90..90).each do |angle|
    #   (0..4).each do |power|
    #     next
    #     @move_graph
    #   end
    # end
  end

  # @return [String] the output line for rotate and power to use this turn
  def call(line)
    # h_speed: the horizontal speed (in m/s), can be negative.
    # v_speed: the vertical speed (in m/s), can be negative.
    # fuel: the quantity of remaining fuel in liters.
    # rotate: the rotation angle in degrees (-90 to 90). E=0, S=90, W=180 N=270
    # power: the thrust power (0 to 4).
    x, y, h_speed, v_speed, fuel, rotate, power = line.split(" ").map(&:to_f)

    # @points -= [@previous_lander_location]
    @current_lander_location = Point.new(x, y)
    # @points += [@current_lander_location]

    # TODO, use a visibility graph to build the actual path. For now asuming landing is visible from lander
    # Array of sorted Segments from current lander position to preferred landing site
    @closest_point_to_land =
      if x < landing_line.p1.x
        # landing_line.p1
        # adding some safety margins
        Point.new(landing_line.p1.x+50, landing_line.p1.y+50)
      elsif landing_line.p2.x < x
        # landing_line.p2
        Point.new(landing_line.p2.x-50, landing_line.p2.y+50)
      else # on top of landing strip, just descend
        Point.new(x, landing_line.p1.y+10)
      end

    direct_line_to_landing = Segment.new(@current_lander_location, @closest_point_to_land)

    @path_to_landing =
      if direct_line_to_landing.length < 200
        [direct_line_to_landing]
      else
        point_just_above_landing = Point.new(@closest_point_to_land.x, @closest_point_to_land.y+200)
        [
          Segment.new(@current_lander_location, point_just_above_landing),
          direct_line_to_landing
        ]
      end

    debug "Path to landing: #{@path_to_landing}"

    # given that the lander can't change settings dramatically, there's only a limited number of "moves":
    # 180 degrees * 5 power levels, and only a subset of these can be used given a previous move.
    # To start, we'll keep things simple - ignore inertia and only consider 8 cardinal directions with hardcoded "move" for each:

    direction = @path_to_landing.first.eight_sector_angle
    debug "Direction is: #{direction}"

    inertia_direction = Segment.new(Point.new(0, 0), Point.new(h_speed, v_speed)).eight_sector_angle
    debug "Inertia direction is: #{inertia_direction}"

    # setting breadcrumb for next round
    @previous_lander_location = @current_lander_location

    # breaking if excessive inertia
    if v_speed.abs > MAX_SAFE_VERTICAL_SPEED
      debug "UNCONTROLLED FALLING DETECTED, BREAKING!"
      return "0 4"
    end

    if _over_landing_strip = @path_to_landing.size <= 2 && (landing_line.p1.x..landing_line.p2.x).include?(x)
      debug "Above landing strip, time to stabilise and land!"

      if h_speed.abs > MAX_SAFE_HORIZONTAL_SPEED && LANDING_DIRECTIONS.include?(direction)
        debug "HORIZONTAL SLIP DETECTED, BREAKING!"
        if (_going_right_too_fast = RIGHT_DIRECTIONS.include?(inertia_direction))
          return "23 4"
        else
          return "-23 4"
        end
      end

      if _brace_for_impact = @path_to_landing.first.dx.abs < 400 && @path_to_landing.first.dy.abs < 300
        if v_speed > MAX_SAFE_VERTICAL_SPEED*(2/3.to_f)
          return "0 3"
        else
          return "0 2"
        end
      end

      if h_speed.positive?
        return "15 3"
      else
        return "-15 3"
      end
    else # as in keep cruisin'
      debug "Not above landing strip, keeping cruise on"
      if v_speed.abs > MAX_SAFE_VERTICAL_CRUISE_SPEED
        debug "EXCEEDING CRUISE deltaY, stabilising!"

        if (_going_down_too_fast = v_speed.negative?)
          return "0 4"
        else
          # return "0 2"
        end
      end

      unless h_speed.abs < MAX_SAFE_HORIZONTAL_SPEED
        # breaking based on inertia and estimated break path
        seconds_to_cover_ground = (@path_to_landing.first.dx.abs / h_speed.abs).round
        seconds_to_break_to_safe_speed = ((h_speed.abs - MAX_SAFE_HORIZONTAL_SPEED) /1.5).round

        debug "Traveling at current speed of #{h_speed}, covering #{@path_to_landing.first.dx.abs}m will take #{seconds_to_cover_ground}s, but breaking #{seconds_to_break_to_safe_speed}s"
        if seconds_to_break_to_safe_speed >= seconds_to_cover_ground || seconds_to_cover_ground < 10
          debug "Breaking to keep overshoot to a minumum"
          if (_going_right_too_fast = RIGHT_DIRECTIONS.include?(inertia_direction))
            return "22 4"
          else
            return "-22 4"
          end
        end
      end

      # rotate power. rotate is the desired rotation angle. power is the desired thrust power.
      case direction
      when 1
        "-30 4"
      when 2
        "-5 4"
      when 3
        "5 4"
      when 4
        "30 4"
      when 5
        "30 4"
      when 6 # landing
        "25 4"
      when 7 # landing
        "-25 4"
      when 8
        "-30 4"
      else
        raise("Unkown direction")
      end
    end
  end
end

# == GAME INIT ==
@surface_n = gets.to_i # the number of points used to draw the surface of Mars.
@surface = []

@surface_n.times do
  land_x, land_y = gets.split(" ").map(&:to_i)
  @surface << Point.new(land_x, land_y)
end

@surface.each do |point|
  debug point.to_s
end

controller = Controller.new(@surface)
