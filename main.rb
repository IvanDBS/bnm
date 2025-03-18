# frozen_string_literal: true

require 'net/http'
require 'nokogiri'
require 'telegram/bot'
require 'date'
require 'logger'

module BNMBot
  class Configuration
    CURRENCY_IDS = {
      'EUR' => '47',
      'USD' => '44',
      'UAH' => '53',
      'RON' => '49',
      'RUB' => '51'
    }.freeze

    TRANSLATIONS = {
      'ro' => {
        'greeting' => 'Bună! 👋 Alegeți una din opțiunile de mai jos:',
        'current_rates' => '💰 Curs Valutar Azi',
        'yesterday_rates' => '📅 Curs Valutar Ieri',
        'comparison' => '📊 Comparație',
        'change_language' => '🌐 Schimbă Limba',
        'error' => 'Ne pare rău, a apărut o eroare. Încercați mai târziu.',
        'productive_day' => 'Să aveți o zi productivă în continuare! 🌟',
        'data_unavailable' => 'Scuze, datele nu sunt disponibile momentan.',
        'rates_header' => 'Curs valutar BNM, %{date}:',
        'comparison_header' => "Comparație curs valutar:\n%{today_date} vs %{yesterday_date}",
        'choose_language' => 'Alegeți limba',
        'select_language' => '🌐 Select language / Alegeți limba / Выберите язык'
      },
      'ru' => {
        'greeting' => 'Привет! 👋 Выберите одну из опций ниже:',
        'current_rates' => '💰 Курс Валют Сегодня',
        'yesterday_rates' => '📅 Курс Валют Вчера',
        'comparison' => '📊 Сравнение',
        'change_language' => '🌐 Сменить Язык',
        'error' => 'Извините, произошла ошибка. Попробуйте позже.',
        'productive_day' => 'Хорошего вам дня! 🌟',
        'data_unavailable' => 'Извините, данные временно недоступны.',
        'rates_header' => 'Курс валют НБМ, %{date}:',
        'comparison_header' => "Сравнение курсов валют:\n%{today_date} vs %{yesterday_date}",
        'choose_language' => 'Выберите язык',
        'select_language' => '🌐 Select language / Alegeți limba / Выберите язык'
      },
      'en' => {
        'greeting' => 'Hello! 👋 Choose one of the options below:',
        'current_rates' => '💰 Exchange Rates Today',
        'yesterday_rates' => '📅 Exchange Rates Yesterday',
        'comparison' => '📊 Comparison',
        'change_language' => '🌐 Change Language',
        'error' => 'Sorry, an error occurred. Please try again later.',
        'productive_day' => 'Have a great day! 🌟',
        'data_unavailable' => 'Sorry, data is temporarily unavailable.',
        'rates_header' => 'NBM Exchange Rates, %{date}:',
        'comparison_header' => "Exchange rates comparison:\n%{today_date} vs %{yesterday_date}",
        'choose_language' => 'Choose language',
        'select_language' => '🌐 Select language / Alegeți limba / Выберите язык'
      }
    }.freeze

    KEYBOARD_BUTTONS = ->(lang) {
      [
        [{ text: TRANSLATIONS[lang]['current_rates'] }],
        [{ text: TRANSLATIONS[lang]['yesterday_rates'] }],
        [{ text: TRANSLATIONS[lang]['comparison'] }],
        [{ text: TRANSLATIONS[lang]['change_language'] }]
      ]
    }

    LANGUAGE_KEYBOARD = [
      [
        { text: '🇷🇴 Română' },
        { text: '🇷🇺 Русский' },
        { text: '🇬🇧 English' }
      ]
    ].freeze
  end

  class ExchangeRateService
    class << self
      def get_rates(date)
        data = fetch_data(date)
        return nil unless data

        parse_rates(data)
      end

      private

      def fetch_data(date)
        url = URI.parse("https://bnm.md/en/official_exchange_rates?get_xml=1&date=#{date}")
        response = Net::HTTP.get_response(url)
        response.body
      rescue StandardError => e
        logger.error("Error fetching data: #{e.message}")
        nil
      end

      def parse_rates(data)
        doc = Nokogiri::XML(data)
        rates = {}
        
        Configuration::CURRENCY_IDS.each do |currency, id|
          rates[currency] = extract_rate(doc, id)
        end
        
        rates
      rescue StandardError => e
        logger.error("Error parsing XML: #{e.message}")
        nil
      end

      def extract_rate(doc, valute_id)
        doc.at_xpath("//Valute[@ID='#{valute_id}']/Value")&.content
      end

      def logger
        @logger ||= Logger.new($stdout)
      end
    end
  end

  class MessageFormatter
    class << self
      def format_current_rates(rates, date, lang)
        return Configuration::TRANSLATIONS[lang]['data_unavailable'] unless rates

        text = "#{Configuration::TRANSLATIONS[lang]['rates_header'] % { date: date }}\n\n"
        rates.each do |currency, rate|
          text += "#{currency}: #{rate} MDL\n"
        end
        text += "\n#{Configuration::TRANSLATIONS[lang]['productive_day']}"
        text
      end

      def format_comparison(today_rates, yesterday_rates, today_date, yesterday_date, lang)
        return Configuration::TRANSLATIONS[lang]['data_unavailable'] unless today_rates && yesterday_rates

        text = Configuration::TRANSLATIONS[lang]['comparison_header'] % {
          today_date: today_date,
          yesterday_date: yesterday_date
        }
        text += "\n\n"

        today_rates.each do |currency, today_rate|
          yesterday_rate = yesterday_rates[currency]
          difference = (today_rate.to_f - yesterday_rate.to_f).round(4)
          arrow = get_trend_arrow(difference)
          
          text += "#{currency}: #{today_rate} MDL #{arrow} (#{difference})\n"
        end
        text
      end

      private

      def get_trend_arrow(difference)
        case
        when difference.positive? then "↑"
        when difference.negative? then "↓"
        else "="
        end
      end
    end
  end

  module HealthMonitor
    class << self
      def initialize_monitoring
        @start_time = Time.now
        @last_message_time = Time.now
        @message_count = 0
        @errors_count = 0
        @logger = Logger.new($stdout)
        @logger.level = Logger::INFO
      end

      def record_message
        @message_count += 1
        @last_message_time = Time.now
      end

      def record_error
        @errors_count += 1
      end

      def check_health
        current_time = Time.now
        uptime = (current_time - @start_time).to_i
        time_since_last_message = (current_time - @last_message_time).to_i

        health_status = {
          uptime_seconds: uptime,
          messages_processed: @message_count,
          errors_count: @errors_count,
          seconds_since_last_message: time_since_last_message,
          memory_usage_mb: `ps -o rss= -p #{Process.pid}`.to_i / 1024
        }

        log_health_status(health_status)
        
        # Alert if no messages for too long
        if time_since_last_message > 3600 # 1 hour
          @logger.warn "⚠️ No messages received in #{time_since_last_message} seconds"
        end

        # Alert if error rate is high
        if @errors_count > 50
          @logger.warn "⚠️ High error count: #{@errors_count} errors"
        end

        # Perform GC if memory usage is high (> 500MB)
        if health_status[:memory_usage_mb] > 500
          @logger.info "Running GC due to high memory usage"
          GC.start
        end
      end

      private

      def log_health_status(status)
        @logger.info "Bot Health Status:"
        @logger.info "├─ Uptime: #{status[:uptime_seconds]} seconds"
        @logger.info "├─ Messages Processed: #{status[:messages_processed]}"
        @logger.info "├─ Errors Count: #{status[:errors_count]}"
        @logger.info "├─ Time Since Last Message: #{status[:seconds_since_last_message]} seconds"
        @logger.info "└─ Memory Usage: #{status[:memory_usage_mb]} MB"
      end
    end
  end

  class Bot
    def initialize(token)
      @token = token
      @user_languages = {}  # Хранение языка для каждого пользователя
      @logger = Logger.new($stdout)
      HealthMonitor.initialize_monitoring
    end

    def run
      @logger.info('Bot started')
      
      # Start health check timer
      health_check_thread = Thread.new do
        loop do
          sleep 300 # Check every 5 minutes
          HealthMonitor.check_health
        end
      end

      Telegram::Bot::Client.run(@token) do |bot|
        begin
          @logger.info('Bot connected to Telegram API')
          bot.listen do |message|
            begin
              HealthMonitor.record_message
              next unless message.respond_to?(:text)  # Skip non-text updates
              handle_message(message, bot)
            rescue StandardError => e
              HealthMonitor.record_error
              @logger.error("Error processing message: #{e.message}")
              if message.respond_to?(:chat) && message.respond_to?(:from)
                user_id = message.from.id
                lang = @user_languages[user_id] || 'ro'
                bot.api.send_message(
                  chat_id: message.chat.id,
                  text: Configuration::TRANSLATIONS[lang]['error']
                )
              end
            end
          end
        rescue Telegram::Bot::Exceptions::ResponseError => e
          HealthMonitor.record_error
          @logger.error("Telegram API Error: #{e.message}")
          retry
        rescue StandardError => e
          HealthMonitor.record_error
          @logger.error("Unexpected error: #{e.message}")
          @logger.error(e.backtrace.join("\n"))
          retry
        end
      end
    ensure
      health_check_thread&.kill
    end

    private

    def handle_message(message, bot)
      return unless message.respond_to?(:text)
      
      user_id = message.from.id
      @user_languages[user_id] ||= 'ro'  # Default language is Romanian

      case message.text
      when '/start'
        handle_start(message, bot)
      when '🇷🇴 Română'
        change_language(message, bot, 'ro')
      when '🇷🇺 Русский'
        change_language(message, bot, 'ru')
      when '🇬🇧 English'
        change_language(message, bot, 'en')
      when Configuration::TRANSLATIONS['ro']['change_language'],
           Configuration::TRANSLATIONS['ru']['change_language'],
           Configuration::TRANSLATIONS['en']['change_language']
        show_language_selection(message, bot)
      when Configuration::TRANSLATIONS['ro']['current_rates'],
           Configuration::TRANSLATIONS['ru']['current_rates'],
           Configuration::TRANSLATIONS['en']['current_rates'],
           '/get_rates'
        handle_current_rates(message, bot)
      when Configuration::TRANSLATIONS['ro']['yesterday_rates'],
           Configuration::TRANSLATIONS['ru']['yesterday_rates'],
           Configuration::TRANSLATIONS['en']['yesterday_rates'],
           '/get_rates_yesterday'
        handle_yesterday_rates(message, bot)
      when Configuration::TRANSLATIONS['ro']['comparison'],
           Configuration::TRANSLATIONS['ru']['comparison'],
           Configuration::TRANSLATIONS['en']['comparison'],
           '/compare_rates'
        handle_comparison(message, bot)
      end
    end

    def change_language(message, bot, lang)
      user_id = message.from.id
      @user_languages[user_id] = lang
      show_main_menu(message, bot, lang)
    end

    def show_language_selection(message, bot)
      markup = Telegram::Bot::Types::ReplyKeyboardMarkup.new(
        keyboard: Configuration::LANGUAGE_KEYBOARD,
        resize_keyboard: true,
        one_time_keyboard: false
      )

      user_id = message.from.id
      lang = @user_languages[user_id] || 'en'

      bot.api.send_message(
        chat_id: message.chat.id,
        text: Configuration::TRANSLATIONS[lang]['select_language'],
        reply_markup: markup
      )
    end

    def show_main_menu(message, bot, lang = nil)
      user_id = message.from.id
      lang ||= @user_languages[user_id]

      markup = Telegram::Bot::Types::ReplyKeyboardMarkup.new(
        keyboard: Configuration::KEYBOARD_BUTTONS.call(lang),
        resize_keyboard: true,
        one_time_keyboard: false
      )

      bot.api.send_message(
        chat_id: message.chat.id,
        text: Configuration::TRANSLATIONS[lang]['greeting'],
        reply_markup: markup
      )
    end

    def handle_start(message, bot)
      show_language_selection(message, bot)
    end

    def handle_current_rates(message, bot)
      user_id = message.from.id
      lang = @user_languages[user_id]
      date = adjust_for_weekend(Date.today)
      rates = ExchangeRateService.get_rates(date.strftime('%d.%m.%Y'))
      
      bot.api.send_message(
        chat_id: message.chat.id,
        text: MessageFormatter.format_current_rates(rates, date.strftime('%d.%m.%Y'), lang)
      )
    end

    def handle_yesterday_rates(message, bot)
      user_id = message.from.id
      lang = @user_languages[user_id]
      yesterday = adjust_for_weekend(Date.today - 1)
      rates = ExchangeRateService.get_rates(yesterday.strftime('%d.%m.%Y'))
      
      bot.api.send_message(
        chat_id: message.chat.id,
        text: MessageFormatter.format_current_rates(rates, yesterday.strftime('%d.%m.%Y'), lang)
      )
    end

    def handle_comparison(message, bot)
      user_id = message.from.id
      lang = @user_languages[user_id]
      today = adjust_for_weekend(Date.today)
      yesterday = adjust_for_weekend(today - 1)
      
      today_rates = ExchangeRateService.get_rates(today.strftime('%d.%m.%Y'))
      yesterday_rates = ExchangeRateService.get_rates(yesterday.strftime('%d.%m.%Y'))
      
      bot.api.send_message(
        chat_id: message.chat.id,
        text: MessageFormatter.format_comparison(
          today_rates,
          yesterday_rates,
          today.strftime('%d.%m.%Y'),
          yesterday.strftime('%d.%m.%Y'),
          lang
        )
      )
    end

    def adjust_for_weekend(date)
      return date - 2 if date.sunday?
      return date - 1 if date.saturday?
      date
    end
  end
end

# Initialize and run the bot
token = ENV['TELEGRAM_BOT_TOKEN'] or raise 'TELEGRAM_BOT_TOKEN not provided'
BNMBot::Bot.new(token).run
