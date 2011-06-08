module GridRest
  class Engine < Rails::Engine
    #rake_tasks do
    #  load "tasks/tiny_mce.rake"
    #end
    config.grid_rest = GridRest

    initializer "grid_rest.load_config" do |app|
      app.config.after_initialize do
        GridRest.load_config!
      end
      #ActiveSupport.on_load(:action_controller) do
      #  GridRest.include_in(self)
      #end
    end
  end
end
