#
# Copyright (c) 2015, Arista Networks, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#   Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
#
#   Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in the
#   documentation and/or other materials provided with the distribution.
#
#   Neither the name of Arista Networks nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL ARISTA NETWORKS
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
# IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
require 'netaddr'
require 'rbeapi/api'

##
# Eos is the toplevel namespace for working with Arista EOS nodes
module Rbeapi
  ##
  # Api is module namespace for working with the EOS command API
  module Api
    ##
    # The Acl class manages the set of standard ACLs.
    class Acl < Entity
      def initialize(node)
        super(node)
        @entry_re = Regexp.new(%r{(\d+)
                                  (?:\ ([p|d]\w+))
                                  (?:\ (any))?
                                  (?:\ (host))?
                                  (?:\ ([0-9]+(?:\.[0-9]+){3}))?
                                  (?:/([0-9]{1,2}))?
                                  (?:\ ([0-9]+(?:\.[0-9]+){3}))?
                                  (?:\ (log))?}x)
      end

      ##
      # get returns the specified ACL from the nodes current configuration.
      #
      # @param [String] :name The ACL name.
      #
      # @return [nil, Hash<Symbol, Object>] Returns the ACL resource as a
      #   Hash.
      def get(name)
        config = get_block("ip access-list standard #{name}")
        return nil unless config

        parse_entries(config)
      end

      ##
      # getall returns the collection of ACLs from the nodes running
      # configuration as a hash. The ACL resource collection hash is
      # keyed by the ACL name.
      #
      # @return [nil, Hash<Symbol, Object>] Returns a hash that represents
      #   the entire ACL collection from the nodes running configuration.
      #   If there are no ACLs configured, this method will return an
      #   empty hash.
      def getall
        acls = config.scan(/ip access-list standard ([^\s]+)/)
        acls.each_with_object({}) do |name, hsh|
          resource = get(name[0])
          hsh[name[0]] = resource if resource
        end
      end

      ##
      # mask_to_prefixlen converts a subnet mask from dotted decimal to
      # bit length
      #
      # @param [String] :mask The dotted decimal subnet mask to convert
      #
      # @return [String] The subnet mask as a valid prefix length
      def mask_to_prefixlen(mask)
        mask = '255.255.255.255' unless mask
        NetAddr::CIDR.create('0.0.0.0/' + mask).netmask_ext
      end

      ##
      # parse_entries scans the nodes configurations and parses
      # the entries within an ACL.
      #
      # @api private
      #
      # @param [String] :config The switch config.
      #
      # @return [Hash<Symbol, Object>] resource hash attribute

      def parse_entries(config)
        entries = {}

        lines = config.scan(/\d+ [p|d].*$/)
        lines.each do |line|
          entry = line.scan(@entry_re).map \
            do |(seqno, act, _anyip, _host, ip, mlen, mask, log)|
            {
              seqno: seqno,
              action: act,
              srcaddr: ip || '0.0.0.0',
              srcprefixlen: mlen || mask_to_prefixlen(mask),
              log: log
            }
          end
          entries[entry[0][:seqno]] = entry[0]
        end
        entries
      end
      private :parse_entries

      ##
      # create will create a new ACL resource in the nodes current
      # configuration with the specified name.  If the create method
      # is called and the ACL already exists, this method will still
      # return true. The ACL will not have any entries. Use add_entry
      # to add entries to the ACL.
      #
      # @eos_version 4.13.7M
      #
      # @commands
      #   ip access-list standard <name>
      #
      # @param [String] :name The ACL name to create on the node. Must
      #   begin with an alphabetic character. Cannot contain spaces or
      #   quotation marks.
      #
      # @return [Boolean] returns true if the command completed successfully
      def create(name)
        configure("ip access-list standard #{name}")
      end

      ##
      # delete will delete an existing ACL resource from the nodes current
      # running configuration.  If the delete method is called and the ACL
      # does not exist, this method will succeed.
      #
      # @eos_version 4.13.7M
      #
      # @commands
      #   no ip access-list standard <name>
      #
      # @param [String] :name The ACL name to delete on the node.
      #
      # @return [Boolean] returns true if the command completed successfully
      def delete(name)
        configure("no ip access-list standard #{name}")
      end

      ##
      # default will configure the ACL using the default keyword.  This
      # command has the same effect as deleting the ACL from the nodes
      # running configuration.
      #
      # @eos_version 4.13.7M
      #
      # @commands
      #   default no ip access-list standard <name>
      #
      # @param [String] :name The ACL name to set to the default value
      #   on the node.
      #
      # @return [Boolean] returns true if the command complete successfully
      def default(name)
        configure("default ip access-list standard #{name}")
      end

      ##
      # build_entry will build the commands to add an entry.
      #
      # @api private
      #
      # @param [Hash] :opts the options for the entry
      # @option :opts  [String] :seqno The sequence number of the entry in
      #   the ACL to add. Default is nil, will be assigned.
      # @option :opts  [String] :action The action triggered by the ACL. Valid
      #   values are 'permit', 'deny', or 'remark'
      # @option :opts  [String] :addr The IP address to permit or deny.
      # @option :opts  [String] :prefixlen The prefixlen for the IP address.
      # @option :opts  [Boolean] :log Triggers an informational log message
      #   to the console about the matching packet.
      #
      # @return [String] returns commands to create an entry
      def build_entry(entry)
        cmds = "#{entry[:seqno]} " if entry[:seqno]
        cmds << "#{entry[:action]} #{entry[:srcaddr]}/#{entry[:srcprefixlen]}"
        cmds << ' log' if entry[:log]
        cmds
      end
      private :build_entry

      ##
      # update_entry will update an entry, identified by the seqno
      # in the ACL specified by name, with the passed in parameters.
      #
      # @eos_version 4.13.7M
      #
      # @param [String] :name The ACL name to update on the node.
      # @param [Hash] :opts the options for the entry
      # @option :opts  [String] :seqno The sequence number of the entry in
      #   the ACL to update.
      # @option :opts  [String] :action The action triggered by the ACL. Valid
      #   values are 'permit', 'deny', or 'remark'
      # @option :opts  [String] :addr The IP address to permit or deny.
      # @option :opts  [String] :prefixlen The prefixlen for the IP address.
      # @option :opts  [Boolean] :log Triggers an informational log message
      #   to the console about the matching packet.
      #
      # @return [Boolean] returns true if the command complete successfully
      def update_entry(name, entry)
        cmds = ["ip access-list standard #{name}"]
        cmds << "no #{entry[:seqno]}"
        cmds << build_entry(entry)
        cmds << 'exit'
        configure(cmds)
      end

      ##
      # add_entry will add an entry to the specified ACL with the
      # passed in parameters.
      #
      # @eos_version 4.13.7M
      #
      # @param [String] :name The ACL name to add an entry to on the node.
      # @param [Hash] :opts the options for the entry
      # @option :opts  [String] :action The action triggered by the ACL. Valid
      #   values are 'permit', 'deny', or 'remark'
      # @option :opts  [String] :addr The IP address to permit or deny.
      # @option :opts  [String] :prefixlen The prefixlen for the IP address.
      # @option :opts  [Boolean] :log Triggers an informational log message
      #   to the console about the matching packet.
      #
      # @return [Boolean] returns true if the command complete successfully
      def add_entry(name, entry)
        cmds = ["ip access-list standard #{name}"]
        cmds << build_entry(entry)
        cmds << 'exit'
        configure(cmds)
      end

      ##
      # remove_entry will remove the entry specified by the seqno for
      # the ACL specified by name.
      #
      # @eos_version 4.13.7M
      #
      # @param [String] :name The ACL name to update on the node.
      # @param [String] :seqno The sequence number of the entry in
      #   the ACL to remove.
      #
      # @return [Boolean] returns true if the command complete successfully
      def remove_entry(name, seqno)
        cmds = ["ip access-list standard #{name}", "no #{seqno}", 'exit']
        configure(cmds)
      end
    end
  end
end
