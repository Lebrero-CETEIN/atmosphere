class HostMetric < Metric

  ITEM_LIMIT = 50

  attr_accessor :body, :id, :results

  def initialize(body, client)
    super(body, client)
  end

  def collect
    qb = QueryBuilder.new
    qb.add_params(:itemids => @id)
    qb.add_params(:history => @type)
    qb.add_params(:limit => ITEM_LIMIT)
    store_results(client.history(qb))
  end

  def collect_last
    reload
    last_value
  end

  def store_results(results)
    @results = results
    evaluated_results
  end

  def evaluated_results
    @results.map{ |measure| MetricValueEvaluator.evaluate(@type, measure["value"])}
  end

  def last_value
    MetricValueEvaluator.evaluate(@type, @last_value)
  end

end