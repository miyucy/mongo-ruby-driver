# Copyright (C) 2014 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Mongo
  class Server

    # Defines behaviour around what features a specific server supports.
    #
    # @since 2.0.0
    class Features

      # List of features and the wire protocol version they appear in.
      #
      # @since 2.0.0
      MAPPINGS = {
        :list_collections => 3,
        :list_indexes => 3,
        :scram_sha_1 => 3,
        :write_command => 2
      }.freeze

      # The wire protocol versions that this version of the driver supports.
      #
      # @since 2.0.0
      DRIVER_WIRE_VERSIONS = (0..3).freeze

      # Create the methods for each mapping to tell if they are supported.
      #
      # @since 2.0.0
      MAPPINGS.each do |name, version|

        # Determine whether or not the feature is enabled.
        #
        # @example Is a feature enabled?
        #   features.list_collections_enabled?
        #
        # @return [ true, false ] If the feature is enabled.
        #
        # @since 2.0.0
        define_method("#{name}_enabled?") do
          server_wire_versions.include?(MAPPINGS[name])
        end
      end

      # @return [ Range ] server_wire_versions The server's supported wire
      #   versions.
      attr_reader :server_wire_versions

      # Initialize the features.
      #
      # @example Initialize the features.
      #   Features.new(0..3)
      #
      # @param [ Range ] server_wire_versions The server supported wire
      #   versions.
      #
      # @since 2.0.0
      def initialize(server_wire_versions)
        @server_wire_versions = server_wire_versions
        check_driver_support!
      end

      # Raised when the driver does not support the complete set of server
      # features.
      #
      # @since 2.0.0
      class Unsupported < DriverError

        # Initialize the exception.
        #
        # @example Initialize the exception.
        #   Unsupported.new(0..3)
        #
        # @param [ Range ] server_wire_versions The server's supported wire
        #   versions.
        #
        # @since 2.0.0
        def initialize(server_wire_versions)
          super(
            "This version of the driver, #{Mongo::VERSION}, only supports wire " +
            "protocol versions #{DRIVER_WIRE_VERSIONS} and the server supports " +
            "wire versions #{server_wire_versions}. Please upgrade the driver " +
            "to be able to support this server version."
          )
        end
      end

      private

      def check_driver_support!
        if DRIVER_WIRE_VERSIONS.max < server_wire_versions.max
          raise Unsupported.new(server_wire_versions)
        end
      end
    end
  end
end