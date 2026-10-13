# frozen_string_literal: true

module OpenLanes
  module Live
    # What a person has said about the run that the plan folders do not
    # record: the questions they are holding, the agents they asked to hold,
    # and the models chosen for agents' next rounds.
    #
    # Held in the engine, and kept by {RunRecord} in Redis and in
    # `.plans/openlanes-state.json` (W6), so an engine that restarts still
    # knows them. Every change moves {#seq} on by one, which is how the
    # record tells which of its two copies is newer. A model choice also
    # lives in the executor, which is what applies it; this copy is what the
    # page is shown and what a restart hands back to the executor.
    class RunState
      def initialize
        @mutex = Mutex.new
        @held_questions = []
        @held_cars = []
        @models = {}
        @seq = 0
      end

      # @param id [String] `"<ordinal>/B<n>"`
      # @param held [Boolean]
      # @return [void]
      def hold_question(id, held: true) = toggle(@held_questions, id, held)

      # @param id [String]
      # @return [Boolean]
      def question_held?(id) = @mutex.synchronize { @held_questions.include?(id) }

      # @param key [String] `"<ordinal>/<agent>"`
      # @param held [Boolean]
      # @return [void]
      def hold_car(key, held: true) = toggle(@held_cars, key, held)

      # @param key [String]
      # @return [Boolean]
      def car_held?(key) = @mutex.synchronize { @held_cars.include?(key) }

      # @param key [String] `"<ordinal>/<agent>"`
      # @param model [String, nil] nil forgets the choice
      # @return [void]
      def choose_model(key, model)
        @mutex.synchronize do
          next if @models[key] == model

          model ? @models[key] = model : @models.delete(key)
          @seq += 1
        end
      end

      # @param key [String]
      # @return [String, nil] the model queued for that agent's next round
      def model_for(key) = @mutex.synchronize { @models[key] }

      # @return [Hash{String => String}] `"<ordinal>/<agent>"` to model, a copy
      def models = @mutex.synchronize { @models.dup }

      # @return [Integer] changes made since the run's state was first recorded
      def seq = @mutex.synchronize { @seq }

      # As {RunRecord} keeps it.
      #
      # @return [Hash]
      def to_h
        @mutex.synchronize do
          { "seq" => @seq, "held_questions" => @held_questions.dup, "held_cars" => @held_cars.dup,
            "models" => @models.dup }
        end
      end

      # Take back what {#to_h} wrote, sequence number included.
      #
      # @param data [Hash]
      # @return [self]
      def restore(data)
        @mutex.synchronize do
          @held_questions = Array(data["held_questions"]).map(&:to_s)
          @held_cars = Array(data["held_cars"]).map(&:to_s)
          @models = (data["models"].is_a?(Hash) ? data["models"] : {}).to_h { |k, v| [k.to_s, v.to_s] }
          @seq = data["seq"].to_i
        end
        self
      end

      private

      # @return [void]
      def toggle(list, item, on)
        @mutex.synchronize do
          next if list.include?(item) == on

          on ? list.push(item) : list.delete(item)
          @seq += 1
        end
      end
    end
  end
end
