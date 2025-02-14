require 'date'

module Marley

  # = Articles
  # Data source is Marley::Configuration::DATA_DIRECTORY (set in <tt>config.yml</tt>)
  class Post
    
    attr_reader :id, :title, :intro, :body, :body_html, :meta, :published_on, :updated_on, :published, :comments
    
    # comments are referenced via +has_many+ in Comment
    
    def initialize(options={})
      options.each_pair { |key, value| instance_variable_set("@#{key}", value) if self.respond_to? key }
    end
  
    class << self

      def all(options={})
        self.find_all options.merge(:draft => true)
      end
    
      def published(options={})
        self.find_all options.merge(:draft => false)
      end
      
      def front_page(options={})
        self.published[0..(CONFIG['blog']['front_page_articles']-1)]
      end
  
      def [](id, options={})
        self.find_one(id, options)
      end
      alias :find :[] # For +belongs_to+ in Comment

    end
    
    def categories
      self.meta['categories'] if self.meta and self.meta['categories']
    end

    def permalink
      "/#{id}.html"
    end
            
    private
    
    def self.find_all(options={})
      options[:except] ||= ['body', 'body_html']
      posts = []
      self.extract_posts_from_directory(options).each do |file|
        attributes = self.extract_post_info_from(file, options)
        attributes.merge!( :comments => Marley::Comment.find_all_by_post_id(attributes[:id], :select => ['id']) )
        posts << self.new( attributes )
      end
      return posts.reverse
    end
    
    def self.find_one(id, options={})
      directory = self.load_directories_with_posts(options).select { |dir| dir =~ Regexp.new("#{id}") }
      options.merge!( {:draft => true} )
      # FIXME : Refactor this mess!
      return if directory.empty?
      directory = directory.first
      return unless directory or !File.exist?(directory)
      file = Dir["#{directory}/*.txt"].first
      self.new( self.extract_post_info_from(file, options).merge( :comments => Marley::Comment.find_all_by_post_id(id) ) )
    end
    
    # Returns directories in data directory. Default is published only (no <tt>.draft</tt> in name)
    def self.load_directories_with_posts(options={})
      if options[:draft]
        Dir[File.join(Configuration::DATA_DIRECTORY, '*')].select { |dir| File.directory?(dir)  }.sort
      else
        Dir[File.join(Configuration::DATA_DIRECTORY, '*')].select { |dir| File.directory?(dir) and not dir.include?('.draft')  }.sort
      end
    end
    
    # Loads all directories in data directory and returns first <tt>.txt</tt> file in each one
    def self.extract_posts_from_directory(options={})
      self.load_directories_with_posts(options).collect { |dir| Dir["#{dir}/*.txt"].first }.compact
    end
    
    # Extracts post information from the directory name, file contents, modification time, etc
    # Returns hash which can be passed to <tt>Marley::Post.new()</tt>
    # Extracted attributes can be configured with <tt>:except</tt> and <tt>:only</tt> options
    def self.extract_post_info_from(file, options={})
      raise ArgumentError, "#{file} is not a readable file" unless File.exist?(file) and File.readable?(file)
      options[:except] ||= []
      options[:only]   ||= Marley::Post.instance_methods # FIXME: Refaktorovat!!
      dirname       = File.dirname(file).split('/').last
      file_content  = File.read(file)
      meta_content  = file_content.slice!( self.regexp[:meta] )
      body          = file_content.sub( self.regexp[:title], '').sub( self.regexp[:intro], '').strip
      post          = Hash.new

      post[:id]           = dirname.sub(self.regexp[:id], '\1').sub(/\.draft$/, '')
      post[:title], post[:published_on] = file_content.scan( self.regexp[:title_with_date] ).first
      post[:title]        = file_content.scan( self.regexp[:title] ).first.to_s.strip if post[:title].nil?
      post[:published_on] = DateTime.parse( post[:published_on] ) rescue File.mtime( File.dirname(file) )

      post[:intro]        = file_content.scan( self.regexp[:intro] ).first.to_s.strip unless options[:except].include? 'intro' or
                                                                                      not options[:only].include? 'intro'
      post[:body]         = body                                                      unless options[:except].include? 'body' or
                                                                                      not options[:only].include? 'body'
      post[:body_html]    = RDiscount::new( body ).to_html                            unless options[:except].include? 'body_html' or
                                                                                      not options[:only].include? 'body_html'
      post[:meta]         = ( meta_content ) ? YAML::load( meta_content.scan( self.regexp[:meta]).to_s ) : 
                                               nil unless options[:except].include? 'meta' or not options[:only].include? 'meta'
                                                                                      not options[:only].include? 'published_on'
      post[:updated_on]   = File.mtime( file )                                        unless options[:except].include? 'updated_on' or
                                                                                      not options[:only].include? 'updated_on'
      post[:published]    = !dirname.match(/\.draft$/)                                unless options[:except].include? 'published' or
                                                                                      not options[:only].include? 'published'
      return post
    end
    
    def self.regexp
      { :id    => /^\d{0,4}-{0,1}(.*)$/,
        :title => /^#\s*(.*)\s+$/,
        :title_with_date => /^#\s*(.*)\s+\(([0-9\/]+)\)$/,
        :published_on => /.*\s+\(([0-9\/]+)\)$/,
        :intro => /^([^\#\n]+\n)$/, 
        :meta  => /^\{\{\n(.*)\}\}\n$/mi # Multiline Regexp 
      } 
    end
  
  end

end
