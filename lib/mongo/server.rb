# Copyright (C) 2014-2017 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'mongo/server/connectable'
require 'mongo/server/connection'
require 'mongo/server/connection_pool'
require 'mongo/server/context'
require 'mongo/server/description'
require 'mongo/server/monitor'

module Mongo

  # Represents a single server on the server side that can be standalone, part of
  # a replica set, or a mongos.
  #
  # @since 2.0.0
  class Server
    extend Forwardable
    include Monitoring::Publishable

    # @return [ String ] The configured address for the server.
    attr_reader :address

    # @return [ Cluster ] cluster The server cluster.
    attr_reader :cluster

    # @return [ Monitor ] monitor The server monitor.
    attr_reader :monitor

    # @return [ Hash ] The options hash.
    attr_reader :options

    # @return [ Monitoring ] monitoring The monitoring.
    attr_reader :monitoring

    # The default time in seconds to timeout a connection attempt.
    #
    # @since 2.4.3
    CONNECT_TIMEOUT = 10.freeze

    # Get the description from the monitor and scan on monitor.
    def_delegators :monitor, :description, :scan!, :heartbeat_frequency, :last_scan, :compressor
    alias :heartbeat_frequency_seconds :heartbeat_frequency

    # Delegate convenience methods to the monitor description.
    def_delegators :description,
                   :arbiter?,
                   :features,
                   :ghost?,
                   :max_wire_version,
                   :max_write_batch_size,
                   :max_bson_object_size,
                   :max_message_size,
                   :tags,
                   :average_round_trip_time,
                   :mongos?,
                   :other?,
                   :primary?,
                   :replica_set_name,
                   :secondary?,
                   :standalone?,
                   :unknown?,
                   :unknown!,
                   :last_write_date,
                   :logical_session_timeout

    # Get the app metadata from the cluster.
    def_delegators :cluster,
                   :app_metadata,
                   :cluster_time,
                   :update_cluster_time

    # Is this server equal to another?
    #
    # @example Is the server equal to the other?
    #   server == other
    #
    # @param [ Object ] other The object to compare to.
    #
    # @return [ true, false ] If the servers are equal.
    #
    # @since 2.0.0
    def ==(other)
      return false unless other.is_a?(Server)
      address == other.address
    end

    # Get a new context for this server in which to send messages.
    #
    # @example Get the server context.
    #   server.context
    #
    # @return [ Mongo::Server::Context ] context The server context.
    #
    # @since 2.0.0
    #
    # @deprecated Will be removed in version 3.0
    def context
      Context.new(self)
    end

    # Determine if a connection to the server is able to be established and
    # messages can be sent to it.
    #
    # @example Is the server connectable?
    #   server.connectable?
    #
    # @return [ true, false ] If the server is connectable.
    #
    # @since 2.1.0
    def connectable?
      with_connection do |connection|
        connection.connectable?
      end
    end

    # Disconnect the server from the connection.
    #
    # @example Disconnect the server.
    #   server.disconnect!
    #
    # @return [ true ] Always tru with no exception.
    #
    # @since 2.0.0
    def disconnect!
      pool.disconnect!
      monitor.stop! and true
    end

    # When the server is flagged for garbage collection, stop the monitor
    # thread.
    #
    # @example Finalize the object.
    #   Server.finalize(monitor)
    #
    # @param [ Server::Monitor ] monitor The server monitor.
    #
    # @since 2.2.0
    def self.finalize(monitor)
      proc { monitor.stop! }
    end

    # Instantiate a new server object. Will start the background refresh and
    # subscribe to the appropriate events.
    #
    # @api private
    #
    # @example Initialize the server.
    #   Mongo::Server.new('127.0.0.1:27017', cluster, monitoring, listeners)
    #
    # @note Server must never be directly instantiated outside of a Cluster.
    #
    # @param [ Address ] address The host:port address to connect to.
    # @param [ Cluster ] cluster  The cluster the server belongs to.
    # @param [ Monitoring ] monitoring The monitoring.
    # @param [ Event::Listeners ] event_listeners The event listeners.
    # @param [ Hash ] options The server options.
    #
    # @since 2.0.0
    def initialize(address, cluster, monitoring, event_listeners, options = {})
      @address = address
      @cluster = cluster
      @monitoring = monitoring
      @options = options.freeze
      publish_sdam_event(
        Monitoring::SERVER_OPENING,
        Monitoring::Event::ServerOpening.new(address, cluster.topology)
      )
      @monitor = Monitor.new(address, event_listeners, options.merge(app_metadata: cluster.app_metadata))
      monitor.scan!
      monitor.run!
      ObjectSpace.define_finalizer(self, self.class.finalize(monitor))
    end

    # Get a pretty printed server inspection.
    #
    # @example Get the server inspection.
    #   server.inspect
    #
    # @return [ String ] The nice inspection string.
    #
    # @since 2.0.0
    def inspect
      "#<Mongo::Server:0x#{object_id} address=#{address.host}:#{address.port}>"
    end

    # Get the connection pool for this server.
    #
    # @example Get the connection pool for the server.
    #   server.pool
    #
    # @return [ Mongo::Pool ] The connection pool.
    #
    # @since 2.0.0
    def pool
      @pool ||= cluster.pool(self)
    end

    # Determine if the provided tags are a subset of the server's tags.
    #
    # @example Are the provided tags a subset of the server's tags.
    #   server.matches_tag_set?({ 'rack' => 'a', 'dc' => 'nyc' })
    #
    # @param [ Hash ] tag_set The tag set to compare to the server's tags.
    #
    # @return [ true, false ] If the provided tags are a subset of the server's tags.
    #
    # @since 2.0.0
    def matches_tag_set?(tag_set)
      tag_set.keys.all? do |k|
        tags[k] && tags[k] == tag_set[k]
      end
    end

    # Restart the server monitor.
    #
    # @example Restart the server monitor.
    #   server.reconnect!
    #
    # @return [ true ] Always true.
    #
    # @since 2.1.0
    def reconnect!
      monitor.restart! and true
    end

    # Execute a block of code with a connection, that is checked out of the
    # server's pool and then checked back in.
    #
    # @example Send a message with the connection.
    #   server.with_connection do |connection|
    #     connection.dispatch([ command ])
    #   end
    #
    # @return [ Object ] The result of the block execution.
    #
    # @since 2.3.0
    def with_connection(&block)
      pool.with_connection(&block)
    end

    # Handle authentication failure.
    #
    # @example Handle possible authentication failure.
    #   server.handle_auth_failure! do
    #     Auth.get(user).login(self)
    #   end
    #
    # @raise [ Auth::Unauthorized ] If the authentication failed.
    #
    # @return [ Object ] The result of the block execution.
    #
    # @since 2.3.0
    def handle_auth_failure!
      yield
    rescue Auth::Unauthorized
      unknown!
      raise
    end

    # Will writes sent to this server be retried.
    #
    # @example Will writes be retried.
    #   server.retry_writes?
    #
    # @return [ true, false ] If writes will be retried.
    #
    # @note Retryable writes are only available on server versions 3.6+ and with
    #   sharded clusters or replica sets.
    #
    # @since 2.5.0
    def retry_writes?
      !!(features.sessions_enabled? && logical_session_timeout && !standalone?)
    end
  end
end
