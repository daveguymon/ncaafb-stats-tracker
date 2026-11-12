module DataSourceInjection
  def get(path, **options)
    if @test_data_source_factory
      options[:env] = (options[:env] || {}).merge("ncaafb.data_source_factory" => @test_data_source_factory)
    end
    super(path, **options)
  end

  def with_data_source_factory(factory)
    previous = @test_data_source_factory
    @test_data_source_factory = factory
    yield
  ensure
    @test_data_source_factory = previous
  end

  def with_client(client, &block)
    client.define_singleton_method(:request_metadata) { [] } unless client.respond_to?(:request_metadata)
    factory = Sportradar::Ncaafb::DataSourceFactory.new(live_builder: ->(visitor_key:) { client })
    with_data_source_factory(factory, &block)
  end
end
