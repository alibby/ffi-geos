# encoding: UTF-8
# frozen_string_literal: true

module Geos
  class LineString < Geometry
    include Enumerable

    def each
      if block_given?
        self.num_points.times do |n|
          yield self.point_n(n)
        end
        self
      else
        self.num_points.times.collect { |n|
          self.point_n(n)
        }.to_enum
      end
    end

    if FFIGeos.respond_to?(:GEOSGeomGetNumPoints_r)
      def num_points
        FFIGeos.GEOSGeomGetNumPoints_r(Geos.current_handle_pointer, self.ptr)
      end
    else
      def num_points
        self.coord_seq.length
      end
    end

    def point_n(n)
      if n < 0 || n >= self.num_points
        raise Geos::IndexBoundsError.new
      else
        cast_geometry_ptr(
          FFIGeos.GEOSGeomGetPointN_r(Geos.current_handle_pointer, self.ptr, n), {
            :srid_copy => self.srid
          }
        )
      end
    end

    def [](*args)
      if args.length == 1 && args.first.is_a?(Numeric) && args.first >= 0
        self.point_n(args.first)
      else
        self.to_a[*args]
      end
    end
    alias_method :slice, :[]

    def offset_curve(width, options = {})
      options = Constants::BUFFER_PARAM_DEFAULTS.merge(options)

      cast_geometry_ptr(FFIGeos.GEOSOffsetCurve_r(
          Geos.current_handle_pointer,
          self.ptr,
          width,
          options[:quad_segs],
          options[:join],
          options[:mitre_limit]
      ), {
        :srid_copy => self.srid
      })
    end

    if FFIGeos.respond_to?(:GEOSisClosed_r)
      def closed?
        bool_result(FFIGeos.GEOSisClosed_r(Geos.current_handle_pointer, self.ptr))
      end
    end

    def to_linear_ring
      if self.closed?
        Geos.create_linear_ring(self.coord_seq, :srid => pick_srid_according_to_policy(self.srid))
      else
        self_cs = self.coord_seq.to_a
        self_cs.push(self_cs[0])

        Geos.create_linear_ring(self_cs, :srid => pick_srid_according_to_policy(self.srid))
      end
    end

    def to_polygon
      self.to_linear_ring.to_polygon
    end

    def dump_points(cur_path = [])
      cur_path.concat(self.to_a)
    end

    def snap_to_grid!(*args)
      if !self.empty?
        cs = self.coord_seq.snap_to_grid!(*args)

        if cs.length == 0
          @ptr = Geos.create_empty_line_string(:srid => self.srid).ptr
        elsif cs.length <= 1
          raise Geos::InvalidGeometryError.new("snap_to_grid! produced an invalid number of points in for a LineString - found #{cs.length} - must be 0 or > 1")
        else
          @ptr = Geos.create_line_string(cs).ptr
        end
      end

      self
    end

    def snap_to_grid(*args)
      ret = self.dup.snap_to_grid!(*args)
      ret.srid = pick_srid_according_to_policy(self.srid)
      ret
    end

    %w{ max min }.each do |op|
      %w{ x y }.each do |dimension|
        self.class_eval(<<-EOF, __FILE__, __LINE__ + 1)
          def #{dimension}_#{op}
            unless self.empty?
              self.coord_seq.#{dimension}_#{op}
            end
          end
        EOF
      end

      self.class_eval(<<-EOF, __FILE__, __LINE__ + 1)
        def z_#{op}
          unless self.empty?
            if self.has_z?
              self.coord_seq.z_#{op}
            else
              0
            end
          end
        end
      EOF
    end

    %w{
      affine
      rotate
      rotate_x
      rotate_y
      rotate_z
      scale
      trans_scale
      translate
    }.each do |m|
      self.class_eval(<<-EOF, __FILE__, __LINE__ + 1)
        def #{m}!(*args)
          unless self.empty?
            self.coord_seq.#{m}!(*args)
          end

          self
        end

        def #{m}(*args)
          ret = self.dup.#{m}!(*args)
          ret.srid = pick_srid_according_to_policy(self.srid)
          ret
        end
      EOF
    end
  end
end
