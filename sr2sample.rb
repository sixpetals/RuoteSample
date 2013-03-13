require 'rufus-json/automatic'
require 'ruote'
require 'ruote/storage/fs_storage'

ruote = Ruote::Dashboard.new(
  Ruote::Worker.new(
    Ruote::FsStorage.new('ruote_work')))



ruote.noisy = ENV['NOISY'] == 'true'


class SessionStarter < Ruote::Participant
  def on_workitem
    puts "Session started!"

    reply
  end
end

class SessionFinisher < Ruote::Participant
  def on_workitem
    puts "Session finished!"

    reply
  end
end

class Dealer < Ruote::Participant
  def on_workitem
    subjectId = workitem.fields['SubjectId']
    periodNo = workitem.fields['DealerPeriodNo']
    money = workitem.fields['Money'].to_i
    stock = workitem.fields['Stock'].to_i
    type = workitem.fields['Type'].to_i

    wait_time = rand(5)
    sleep(wait_time)

    workitem.fields['Money'] = money-10
    workitem.fields['Stock'] = stock+1

    puts "[PeriodNo=#{periodNo.to_s}][SubjectNo=#{subjectId.to_s}] This subject dealed."

    reply
  end
end

class TreatmentFinisher < Ruote::Participant
  def on_workitem
    subjectId = workitem.fields['SubjectId']
    periodNo = workitem.fields['DealerPeriodNo']
    money = workitem.fields['Money'].to_i
    stock = workitem.fields['Stock'].to_i
    co2Reduction = workitem.fields['CO2Reduction'].to_i
    puts "[SubjectId=#{subjectId.to_s}]All Period Finished! This subject has #{money.to_s} point. CO2 reduction is #{co2Reduction} point."

    reply
  end
end

class StockManetizer < Ruote::Participant
  def on_workitem
    subjectId = workitem.fields['SubjectId']
    periodNo = workitem.fields['DealerPeriodNo']
    money = workitem.fields['Money'].to_i
    stock = workitem.fields['Stock'].to_i
    co2Reduction = workitem.fields['CO2Reduction'].to_i
    devidedFactor = workitem.fields['PeriodStockFactor'][periodNo].to_i
    co2Reductionfactor = workitem.fields['PeriodCO2ReductionFactor'][periodNo].to_i


    dividend = stock * devidedFactor
    co2ReductionDividend = stock * co2Reductionfactor

    puts "[PeriodNo=#{periodNo.to_s}][SubjectId=#{subjectId.to_s}] Dividend is #{dividend.to_s}. CO2 Reduction is #{co2ReductionDividend.to_s}"

    workitem.fields['Money'] = money + dividend
    workitem.fields['CO2Reduction'] = co2Reduction + co2ReductionDividend

    reply
  end
end




class TimeKeeper < Ruote::Participant
  def on_workitem

    sleep(20)

    reply
  end
end

class PeriodStarter < Ruote::Participant
  def on_workitem
    periodNo = workitem.fields['TimekeeperPeriodNo']

    puts "[PeriodNo=#{periodNo.to_s}]Ready!"
    reply
  end
end

class PeriodDataInitializer < Ruote::Participant
  def on_workitem
    periodNo = workitem.fields['PeriodDataInitializerPeriodNo']

    workitem.fields['PeriodStockFactor'] ||= Hash::new
    workitem.fields['PeriodStockFactor'][periodNo] =  [0,2,7,15][rand(4)]
    workitem.fields['PeriodCO2ReductionFactor'] ||= Hash::new
    workitem.fields['PeriodCO2ReductionFactor'][periodNo] =  [0,2,7,15][rand(4)]


    puts "[PeriodNo=#{periodNo.to_s}]Stock factor is #{workitem.fields['PeriodStockFactor'][periodNo].to_s}. CO2 reduction factor is #{workitem.fields['PeriodCO2ReductionFactor'][periodNo]}"
    reply
  end
end

ruote.register 'SessionStarter', SessionStarter
ruote.register 'SessionFinisher', SessionFinisher
ruote.register 'Dealer', Dealer
ruote.register 'TreatmentFinisher', TreatmentFinisher
ruote.register /^TimeKeeper_/, TimeKeeper
ruote.register /^PeriodStarter_/, PeriodStarter
ruote.register 'StockManetizer', StockManetizer
ruote.register 'PeriodDataInitializer', PeriodDataInitializer

pdef = Ruote.define do
  participant :SessionStarter
    iterator :times => 4 ,:to_var => 'index1' do
      set 'PeriodDataInitializerPeriodNo' => '${v:index1}'
      participant :PeriodDataInitializer
    end

  concurrence do
    #TimeKeeper
    iterator :times => 4 ,:to_var => 'index2' do
      set 'TimekeeperPeriodNo' => '${v:index2}'
      wait '2s'
      set 'v:IsPeriodOver' => '-1'
      participant 'PeriodStarter_${f:TimekeeperPeriodNo}'
      participant 'TimeKeeper_${f:TimekeeperPeriodNo}'
      set 'v:IsPeriodOver' => '${f:TimekeeperPeriodNo}'
      wait '2s'
      echo "[PeriodNo=${f:TimekeeperPeriodNo}]Finished!"
    end

    #Dealer
    concurrent_iterator :times => 2 , :to_var => 'index1' do
      sequence do
        set 'SubjectId' => '${v:index1}'
        set 'InitMoney' => 525
        set 'InitStock' =>  1
        set 'InitCO2Reduction' =>  0
        set 'Type'  =>  0

        iterator :times => 4,:to_var => 'index3' do
          set 'DealerPeriodNo' => '${v:index3}'
          set 'Money'  => '${f:InitMoney}'
          set 'Stock' => '${f:InitStock}'
          set 'CO2Reduction' => '${f:InitCO2Reduction}'

          listen :to => 'PeriodStarter_${f:DealerPeriodNo}'
          repeat do
            participant :Dealer
            _break :if => '${v:IsPeriodOver} == ${f:DealerPeriodNo}'
          end
          participant :StockManetizer
        end
        
        participant :TreatmentFinisher
      end

    end
  end

  participant :SessionFinisher
end


wfid = ruote.launch(pdef)
ruote.wait_for(wfid, :timeout => 5 * 60)