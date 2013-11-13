class RecordFilterOptions
  attr_accessor :page, :page_size, :includes, :filters, :serializer, :model_class, :scope, :include_links
  DEFAULT_PAGE_SIZE = 5

  def initialize(serializer, params = {}, scope = nil)
    params.symbolize_keys! if params.respond_to?(:symbolize_keys!)

    @page = 1
    @page_size = nil;
    @includes = []
    @filters = filters_from_params(params, serializer)
    @serializer = serializer
    @model_class = serializer.model_class
    @scope = scope || model_class.send(:all)
    @include_links = true

    @page = params[:page].to_i if params[:page]
    @page_size = params[:page_size].to_i if params[:page_size]
    @includes = params[:includes].split(',').map(&:to_sym) if params[:includes]
  end

  def page?
    @page_size.nil?
  end

  def scope_with_filters
    scope_filter = {}
    @filters.keys.each do |filter|
      value = @filters[filter]
      if value.is_a?(String)
        value = value.split(',')
      end
      scope_filter[filter] = value
    end

    @scope.where(scope_filter)
  end

  def filters_as_url_params
    @filters.sort.map {|k,v| "#{k}=#{v.join(',')}" }.join('&')
  end

  private

  def filters_from_params(params, serializer)
    filters = {}
    serializer.filterable_by.each do |filter|
      [filter, "#{filter}s".to_sym].each do |key|
        filters[filter] = params[key].to_s.split(',') if params[key]
      end
    end
    filters
  end

end

