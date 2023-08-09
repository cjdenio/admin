class Record

    include DnsimpleHelper
    include ActiveModel::Model
    include ActiveModel::Dirty
    include ActiveModel::API
    include ActiveModel::Validations
    include ActiveModel::Conversion
    include Turbo::Broadcastable
    
    attr_accessor :name, :domain_id, :type, :ttl, :priority, :content

    define_attribute_methods :name, :domain_id, :type, :ttl, :priority, :content

    attr_writer :_persisted, :_id
    validates :name, :type, :content, :domain_id, presence: true
    # TODO: more validation

    def initialize(attributes = {})
        super
        if self.name.blank?
            self.name = "@"
        end

        if self.ttl.blank?
            self.ttl = 300
        end
    end



    def self.create(attributes={})
        obj = self.new(attributes)
        obj.save  
        obj.broadcast_append_to('records:main', partial: "records/record")

        obj
    end


    def self.where_host(host)
        domain = Domain.find_by(host: host)
        records = []
        for r in self.all
            if r.domain_id == domain.id  
                records.push(r)
            end
        end

        records
    end

    def self.dnsimple_to_record(obj)

        re = /^((.*)\.)?(.*)$/
        cap = re.match(obj.name)
        subdomain = cap[2]
        domain = cap[3]
        domain_obj = Domain.find_by(host: domain)

        puts domain_obj
        Record.new(
            _id: obj.id,
            _persisted: true, 
            name: subdomain, 
            content: obj.content, 
            priority: obj.priority, 
            ttl: obj.ttl,
            type: obj.type, 
            domain_id: domain_obj&.id 
        )
    end

    def save
        if persisted?
            update_record
        else
            persist
        end
        
        changes_applied

        broadcast_replace_to('records:main', partial: "records/record")
    end

    def persisted?
        @_persisted
    end

    def id
        @_id
    end

    def destroy!
        destroy_record
        broadcast_remove_to('records:main')
    end

    def self.destroy_all_host!(host)
        for r in self.where_host(host)
            r.destroy!
        end
    end

    # TODO: cache, so not on each page load we hit DNSimple unless they don't care :P


    def self.all
        dnsimple_records = client.zones.all_zone_records(Rails.application.credentials.dnsimple.account_id, ENV["DOMAIN"]).data.select { |record| !record.system_record }
        records = []
        for r in dnsimple_records
            if !r.name.blank?
                record = self.dnsimple_to_record(r)

                if record.domain_id
                    records.push(record)
                end
            end
        end

        records
    end

    def self.find(id) 
        found = nil
        for r in self.all
            if r.id == id
               found = r
               break
            end
        end

        found
    end

    # Dirtying methods

    def name=(value)
        if @name != value
            name_will_change!
            @name = value
        end
    end

    def domain_id=(value)
        if @domain_id != value
            domain_id_will_change!
            @domain_id = value
        end
    end

    def type=(value)
        if @type != value
            type_will_change!
            @type = value
        end
    end

    def ttl=(value)
        if @ttl != value
            ttl_will_change!
            @ttl = value
        end
    end

    def priority=(value)
        if @priority != value
            priority_will_change!
            @priority = value
        end
    end

    def content=(value)
        if @content != value
            content_will_change!
            @content = value
        end
    end

    private

    def domain
      Domain.find(domain_id)
    end
    
    def persist
        if @name == "@" || @name == "" || @name == nil
            record = client.zones.create_zone_record(Rails.application.credentials.dnsimple.account_id, ENV["DOMAIN"], name: Domain.find(domain_id).host , type: type, content: content, ttl:  ttl, priority: priority)
            @_id = record.data.id

            ttl = record.data.ttl
            priority = record.data.priority
        else
            if name.ends_with?(".@")
                name.slice!(".@")
            end
      
            name.gsub!("@", Domain.find(domain_id).host)
      
            record = client.zones.create_zone_record(Rails.application.credentials.dnsimple.account_id, ENV["DOMAIN"], name: name + "." + Domain.find(domain_id).host, type: type, content: content, ttl: ttl, priority: priority)
            @_id = record.data.id

            ttl = record.data.ttl
            priority = record.data.priority
        end

        @_persisted = true
    end

    def update_record
        if name == "@" || name == "" || name == nil
            record = client.zones.update_zone_record(Rails.application.credentials.dnsimple.account_id, ENV["DOMAIN"], id, name: Domain.find(domain_id).host , type: type, content: content, ttl:  ttl, priority: priority)
            @_id = record.data.id

            ttl = record.data.ttl
            priority = record.data.priority
        else
            if name.ends_with?(".@")
                name.slice!(".@")
            end
      
            name.gsub!("@", Domain.find(domain_id).host)
      
            record = client.zones.update_zone_record(Rails.application.credentials.dnsimple.account_id, ENV["DOMAIN"], id, name: name + "." + Domain.find(domain_id).host , type: type, content: content, ttl:  ttl, priority: priority)
            @_id = record.data.id

            ttl = record.data.ttl
            priority = record.data.priority
        end

    end

    def destroy_record
        client.zones.delete_zone_record(Rails.application.credentials.dnsimple.account_id, ENV["DOMAIN"], id)
        @_persisted = false
        true
    end
    
end