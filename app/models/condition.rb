class Condition < ActiveRecord::Base
  strip_attributes!

  belongs_to :patient_data
  belongs_to :problem_type
  
  include MatchHelper
  
  @@default_namespaces = {"cda"=>"urn:hl7-org:v3"}
  
  #Reimplementing from MatchHelper
  def section_name
    "Conditions Module"
  end
  
  def validate_c32(document)
    errors = []
    begin
      section = REXML::XPath.first(document,"//cda:section[cda:templateId/@root='2.16.840.1.113883.10.20.1.11']",@@default_namespaces)
      act = REXML::XPath.first(section,"cda:entry/cda:act[cda:templateId/@root='2.16.840.1.113883.10.20.1.27']",@@default_namespaces)
      observation = REXML::XPath.first(act,"cda:entryRelationship[@typeCode='SUBJ']/cda:observation[cda:templateId/@root='2.16.840.1.113883.10.20.1.28']",@@default_namespaces)
      code = REXML::XPath.first(observation,"cda:code[@codeSystem='2.16.840.1.113883.6.96']",@@default_namespaces)
    
      if problem_type
        errors.concat problem_type.validate_c32(code)
      end
    
      errors << match_value(act, "cda:effectiveTime/cda:low/@value", "start_event", start_event.andand.to_formatted_s(:hl7_ts))
      errors << match_value(act, "cda:effectiveTime/cda:high/@value", "end_event", end_event.andand.to_formatted_s(:hl7_ts))
    
      if free_text_name
        text =  REXML::XPath.first(observation,"cda:text",@@default_namespaces)
        deref_text = deref(text)
        if(deref_text != free_text_name)
          errors << ContentError.new(:section=>"Condition",
                                     :error_message=>"Free text name #{free_text_name} does not match #{deref_text}",
                                     :location=>(text)? text.xpath : (code)? code.xpath : section.xpath )
        end
      end 
    rescue
      errors << ContentError.new(:section => 'Condition', 
                                 :error_message => 'Invalid, non-parsable XML for condition data',
                                 :type=>'error',
                                 :location => document.xpath)
    end
    errors.compact
  end
  
  def to_c32(xml)
    xml.entry do
      xml.act("classCode" => "ACT", "moodCode" => "EVN") do
        xml.templateId("root" => "2.16.840.1.113883.10.20.1.27", "assigningAuthorityName" => "CCD")
        xml.templateId("root" => "2.16.840.1.113883.3.88.11.32.7", "assigningAuthorityName" => "HITSP/C32")
        xml.id
        xml.code("nullFlavor"=>"NA")
        if start_event != nil || end_event != nil
          xml.effectiveTime do
            if start_event != nil 
              xml.low("value" => start_event.strftime("%Y%m%d"))
            end
            if end_event != nil
              xml.high("value" => end_event.strftime("%Y%m%d"))
            else
              xml.high("nullFlavor" => "UNK")
            end
          end
        end
        xml.entryRelationship("typeCode" => "SUBJ") do
          xml.observation("classCode" => "OBS", "moodCode" => "EVN") do
            xml.templateId("root" => "2.16.840.1.113883.10.20.1.28", "assigningAuthorityName" => "CCD")
            if problem_type
              xml.code("code" => problem_type.code, 
                       "displayName" => problem_type.name, 
                       "codeSystem" => "2.16.840.1.113883.6.96", 
                       "codeSystemName" => "SNOMED CT")
            end 
            xml.text do
              xml.reference("value" => "#problem-"+id.to_s)
            end
            xml.statusCode("code" => "completed")
            # only write out the coded value if the name of the condition is in the SNOMED list
            if free_text_name
              snowmed_problem = SnowmedProblem.find(:first, :conditions => {:name => free_text_name})
              if snowmed_problem
                xml.value("xsi:type" => "CD", 
                        "code" => snowmed_problem.code, 
                        "displayName" => free_text_name,
                        "codeSystem" => "2.16.840.1.113883.6.96",
                        "codeSystemName" => 'SNOMED CT')
              end
            end
          end
        end
      end
    end
  end
   
  def randomize(birth_date)
    @condition = SnowmedProblem.find(:all).sort_by{rand}.first.name
    self.start_event = DateTime.new(birth_date.year + rand(DateTime.now.year - birth_date.year), rand(12) + 1, rand(28) +1)
    self.problem_type = ProblemType.find(:all).sort_by{rand}.first
    self.free_text_name = @condition
  end
   
  private 
  def deref(code)
   if code
    ref = REXML::XPath.first(code,"cda:reference",@@default_namespaces)
    if ref
       REXML::XPath.first(code.document,"//cda:content[@ID=$id]/text()",@@default_namespaces,{"id"=>ref.attributes['value'].gsub("#",'')}) 
    else
       nil
     end
   end 
 end
  
end
