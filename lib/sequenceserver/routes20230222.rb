require 'json'
require 'tilt/erb'
require 'sinatra/base'

require 'sequenceserver/job'
require 'sequenceserver/blast'
require 'sequenceserver/report'
require 'sequenceserver/database'
require 'sequenceserver/sequence'
require 'sequenceserver/makeblastdb'

module SequenceServer
  # Controller.
  class Routes < Sinatra::Base
    # See
    # http://www.sinatrarb.com/configuration.html
    extend Forwardable
    def_delegators SequenceServer, :config, :sys
    
    configure do
      # We don't need Rack::MethodOverride. Let's avoid the overhead.
      disable :method_override

      # Ensure exceptions never leak out of the app. Exceptions raised within
      # the app must be handled by the app.
      disable :show_exceptions, :raise_errors

      # Make it a policy to dump to 'rack.errors' any exception raised by the
      # app.
      enable :dump_errors

      # We don't want Sinatra do setup any loggers for us. We will use our own.
      set :logging, nil
    end

    # See
    # http://www.sinatrarb.com/intro.html#Mime%20Types
    configure do
      mime_type :fasta, 'text/fasta'
      mime_type :xml,   'text/xml'
      mime_type :tsv,   'text/tsv'
    end

    configure do
      # Public, and views directory will be found here.
      set :root, File.join(__dir__, '..', '..')

      # Allow :frame_options to be configured for Rack::Protection.
      #
      # By default _any website_ can embed SequenceServer in an iframe. To
      # change this, set `:frame_options` config to :deny, :sameorigin, or
      # 'ALLOW-FROM uri'.
      set :protection, lambda {
        frame_options = SequenceServer.config[:frame_options]
        frame_options && { frame_options: frame_options }
      }

      # Serve compressed responses.
      use Rack::Deflater
    end

    # For any request that hits the app,  log incoming params at debug level.
    before do
      logger.debug params
    end

    # Set JSON content type for JSON endpoints.
    before '*.json' do
      content_type 'application/json'
    end

    # Returns base HTML. Rest happens client-side: rendering the search form.
    get '/' do
      erb :search, layout: true
    end
    
    # Borrowed from makeblastdb.rb
    def multipart_database_name?(db_name)
      !(db_name.match(%r{.+/\S+\.\d{2,3}$}).nil?)
    end
    def get_categories(path)
      path
        .gsub(config[:database_dir], '') # remove database_dir from path
        .split('/')
        .reject(&:empty?)[0..-2] # the first entry might be '' if database_dir does not end with /
    end
    def blastdbcmd (line)
      cmd = "blastdbcmd -recursive -list #{line}" \
            ' -list_outfmt "%f	%t	%p	%n	%l	%d	%v"'
      out, err = sys(cmd, path: config[:bin])
      errpat = /BLAST Database error/
      fail BLAST_DATABASE_ERROR.new(cmd, err) if err.match(errpat)
      return out
    rescue CommandFailed => e
      fail BLAST_DATABASE_ERROR.new(cmd, e.stderr)
    end
    
    # Returns data that is used to render the search form client side. These
    # include available databases and user-defined search options.
    get '/searchdata.json' do
      puts "in EDIT get '/searchdata.json' do"
      
      if $DEV_HOST == 'AVhome'
         path_prokka = '/Users/avoorhis/programming/blast-db-alt/'  #SEQF1595.fna*
         path_ncbi = '/Users/avoorhis/programming/blast-db-alt_ncbi/'  #SEQF1595.fna*
         #homdpath = '/mnt/efs/bioinfo/projects/homd_add_genomes_V10.1_all/add_blast/blastdb_ncbi/' #faa,ffn,fna
      else
         path_prokka = '/mnt/efs/bioinfo/projects/homd_add_genomes_V10.1_all/add_blast/blastdb_prokka/' #faa,ffn,fna
         path_ncbi   = '/mnt/efs/bioinfo/projects/homd_add_genomes_V10.1_all/add_blast/blastdb_ncbi/' #faa,ffn,fna
      end
      #puts 'dbs', dbs
      if !params[:gid].nil?
        gid  = params[:gid]
        
        
        # if ext == 'faa'
#            mol_type = 'Protein'
#         elsif ext == 'ffn'
#            mol_type = 'Nucleotide'
#         else  # fna
#            mol_type = 'Nucleotide'
#         end
        fname_faa = gid+".faa"
        fname_fna = gid+".fna"
        fname_ffn = gid+".ffn"
        
        fn_path_faa_p = File.join(path_prokka, 'faa', fname_faa)
        fn_path_fna_p = File.join(path_prokka, 'fna', fname_fna)
        fn_path_ffn_p = File.join(path_prokka, 'ffn', fname_ffn)
        
        fn_path_faa_n = File.join(path_ncbi, 'faa', fname_faa)
        fn_path_fna_n = File.join(path_ncbi, 'fna', fname_fna)
        fn_path_ffn_n = File.join(path_ncbi, 'ffn', fname_ffn)
        
        
        #Database.clear
        
        if !Dir.glob(fn_path_faa_p+'*').empty?
           SequenceServer.init_database2 fn_path_faa_p, 'PROKKA::'+fname_faa, "Protein"
        end
        if !Dir.glob(fn_path_fna_p+'*').empty?
           SequenceServer.init_database2 fn_path_fna_p, 'PROKKA::'+fname_fna, 'Nucleotide'
        end
        if !Dir.glob(fn_path_ffn_p+'*').empty?
           SequenceServer.init_database2 fn_path_ffn_p, 'PROKKA::'+fname_ffn, 'Nucleotide'
        end
        
        if !Dir.glob(fn_path_faa_n+'*').empty?
           SequenceServer.init_database2 fn_path_faa_n, 'NCBI::'+fname_faa, 'Protein'
        end
        if !Dir.glob(fn_path_fna_n+'*').empty?
           SequenceServer.init_database2 fn_path_fna_n, 'NCBI::'+fname_fna, 'Nucleotide'
        end
        if !Dir.glob(fn_path_ffn_n+'*').empty?
           SequenceServer.init_database2 fn_path_ffn_n, 'NCBI::'+fname_ffn, 'Nucleotide'
        end
        searchdata = {
            query: Database.retrieve(params[:query]),
            database: Database.all,
            options: SequenceServer.config[:options]
        }
     
        
     
      else
        
        #Database.clear  # gets rid of others
        #SequenceServer.init_database
        searchdata = {
            query: Database.retrieve(params[:query]),
            database: Database.all,
            options: SequenceServer.config[:options]
        }
      end

      if SequenceServer.config[:databases_widget] == 'tree'
        searchdata.update(tree: Database.tree)
      end

      # If a job_id is specified, update searchdata from job meta data (i.e.,
      # query, pre-selected databases, advanced options used). Query is only
      # updated if params[:query] is not specified.
      update_searchdata_from_job(searchdata) if params[:job_id]

      searchdata.to_json
    end

    # Queues a search job and redirects to `/:jid`.
    post '/' do
      if params[:input_sequence]
        @input_sequence = params[:input_sequence]
        erb :search, layout: true
      else
        job = Job.create(params)
        redirect to("/#{job.id}")
      end
    end

    # Returns results for the given job id in JSON format.  Returns 202 with
    # an empty body if the job hasn't finished yet.
    get '/:jid.json' do |jid|
      job = Job.fetch(jid)
      halt 202 unless job.done?
      Report.generate(job).to_json
    end

    # Returns base HTML. Rest happens client-side: polling for and rendering
    # the results.
    get '/:jid' do
      erb :report, layout: true
    end

    # @params sequence_ids: whitespace separated list of sequence ids to
    # retrieve
    # @params database_ids: whitespace separated list of database ids to
    # retrieve the sequence from.
    # @params download: whether to return raw response or initiate file
    # download
    #
    # Use whitespace to separate entries in sequence_ids (all other chars exist
    # in identifiers) and retreival_databases (we don't allow whitespace in a
    # database's name, so it's safe).
    get '/get_sequence/' do
      sequence_ids = params[:sequence_ids].split(',')
      database_ids = params[:database_ids].split(',')
      sequences = Sequence::Retriever.new(sequence_ids, database_ids)
      sequences.to_json
    end

    post '/get_sequence' do
      sequence_ids = params['sequence_ids'].split(',')
      database_ids = params['database_ids'].split(',')
      sequences = Sequence::Retriever.new(sequence_ids, database_ids, true)
      send_file(sequences.file.path,
                type:     sequences.mime,
                filename: sequences.filename)
    end

    # Download BLAST report in various formats.
    get '/download/:jid.:type' do |jid, type|
      job = Job.fetch(jid)
      out = BLAST::Formatter.new(job, type)
      send_file out.file, filename: out.filename, type: out.mime
    end

    # Catches any exception raised within the app and returns JSON
    # representation of the error:
    # {
    #    title: ...,     // plain text
    #    message: ...,   // plain or HTML text
    #    more_info: ..., // pre-formatted text
    # }
    #
    # If the error class defines `http_status` instance method, its return
    # value will be used to set HTTP status. HTTP status is set to 500
    # otherwise.
    #
    # If the error class defines `title` instance method, its return value
    # will be used as title. Otherwise name of the error class is used as
    # title.
    #
    # All error classes should define `message` instance method that provides
    # a short and simple explanation of the error.
    #
    # If the error class defines `more_info` instance method, its return value
    # will be used as more_info, otherwise `backtrace.join("\n")` is used as
    # more_info.
    error 400..500 do
      error = env['sinatra.error']

      # All errors will have a message.
      error_data = { message: error.message }

      # If error object has a title method, use that, or use name of the
      # error class as title.
      error_data[:title] = if error.respond_to? :title
                             error.title
                           else
                             error.class.name
                           end

      # If error object has a more_info method, use that. If the error does not
      # have more_info, use backtrace.join("\n") as more_info.
      if error.respond_to? :more_info
        error_data[:more_info] = error.more_info
      elsif error.respond_to? :backtrace
        error_data[:more_info] = error.backtrace.join("\n")
      end

      error_data.to_json
    end

    # Get the query sequences, selected databases, and advanced params used.
    def update_searchdata_from_job(searchdata)
      job = Job.fetch(params[:job_id])
      return if job.imported_xml_file

      # Only read job.qfile if we are not going to use Database.retrieve.
      searchdata[:query] = File.read(job.qfile) if !params[:query]

      # Which databases to pre-select.
      searchdata[:preSelectedDbs] = job.databases

      # job.advanced may be nil in case of old jobs. In this case, we do not
      # override searchdata so that default advanced parameters can be applied.
      # Note that, job.advanced will be an empty string if a user deletes the
      # default advanced parameters from the advanced params input field. In
      # this case, we do want the advanced params input field to be empty when
      # the user hits the back button. Thus we do not test for empty string.
      method = job.method.to_sym
      if job.advanced && job.advanced !=
           searchdata[:options][method][:default].join(' ')
        searchdata[:options] = searchdata[:options].deep_copy
        searchdata[:options][method]['last search'] = [job.advanced]
      end
    end
  end
end
