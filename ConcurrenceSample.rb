require 'rufus-json/automatic'
require 'ruote'
require 'ruote/storage/fs_storage'

ruote = Ruote::Dashboard.new(
  Ruote::Worker.new(
    Ruote::FsStorage.new('ruote_work')))

ruote.noisy = ENV['NOISY'] == 'true'


class Alpha < Ruote::Participant
  def on_workitem
    puts 'First'
    reply
  end
end

class Bravo < Ruote::Participant
  def on_workitem
    puts 'Last'
    reply
  end
end

class SplitPart < Ruote::Participant
  def on_workitem

    puts "Worker No #{workitem.fields['Index'].to_s} started!"
    wait_time = rand(10)
    sleep(wait_time)
    puts "Worker No #{workitem.fields['Index'].to_s} #{wait_time.to_s} sec waited!"

    reply
  end
end



ruote.register 'Alpha', Alpha
ruote.register 'Bravo', Bravo
ruote.register 'SplitPart', SplitPart

pdef = Ruote.define do
  sequence do
    concurrent_iterator :times => 4 , :to_var => 'index1' do
      sequence do
        set 'Index' => '${v:index1}'
        repeat :timeout => '30s' do
          participant :SplitPart
        end
      end
    end
    participant :Bravo
  end
end


wfid = ruote.launch(pdef)

ruote.wait_for(wfid)