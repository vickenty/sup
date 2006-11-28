require 'thread'

module Redwood

class PollManager
  include Singleton

  DELAY = 300

  def initialize
    @polling = false
    @last_poll = nil
    
    self.class.i_am_the_instance self

    ::Thread.new do
      while true
        sleep DELAY / 2
        if @last_poll.nil? || (Time.now - @last_poll) >= DELAY
          mbid = BufferManager.say "Polling for new messages..."
          num, numi = poll { |s| BufferManager.say s, mbid }
          BufferManager.clear mbid
          BufferManager.flash "Loaded #{num} new messages, #{numi} to inbox." if num > 0
        end
      end
    end
  end

  def poll
    return [0, 0] if @polling
    @polling = true
    found = {}
    total_num = 0
    total_numi = 0
    Index.usual_sources.each do |source|
      next if source.done?
      yield "Loading from #{source}... "

      start_offset = nil
      num = 0
      num_inbox = 0
      source.each do |offset, labels|
        start_offset ||= offset

        begin
          m = Redwood::Message.new source, offset, labels
          if found[m.id]
            yield "Skipping duplicate message #{m.id}"
            next
          else
            found[m.id] = true
          end
          
          if Index.add_message m
            UpdateManager.relay :add, m
            num += 1
            total_num += 1
            total_numi += 1 if m.labels.include? :inbox
          end
        rescue Redwood::MessageFormatError => e
          yield "Ignoring erroneous message at #{source}##{offset}: #{e.message}"
        end

        if num % 1000 == 0 && num > 0
          elapsed = Time.now - start
          pctdone = (offset.to_f - start_offset) / (source.total.to_f - start_offset)
          remaining = (source.total.to_f - offset.to_f) * (elapsed.to_f / (offset.to_f - start_offset))
          yield "## #{num} (#{(pctdone * 100.0)}% done) read; #{elapsed.to_time_s} elapsed; est. #{remaining.to_time_s} remaining"
        end
      end
      yield "Found #{num} messages" unless num == 0
    end
    yield "Done polling; loaded #{total_num} new messages total"
    @last_poll = Time.now
    @polling = false
    [total_num, total_numi]
  end
end

end
