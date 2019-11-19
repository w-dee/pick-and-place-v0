#include <Arduino.h>
#include <TimerOne.h>

static constexpr uint8_t MAX_BOUNCE = 10; // button debounce maximum count (in ms)

// pin mappings
static constexpr uint8_t PIN_FEED_BUTTON = 3; //!< feed button input
static constexpr uint8_t PIN_FEED_INPUT = 2; //!< feed logic input (active low)
static constexpr uint8_t PIN_GEAR_DIR = 4;//!< gear stepper direction output
static constexpr uint8_t PIN_GEAR_STEP = 5;//!< gear stepper step pulse output
static constexpr uint8_t PIN_REWINDER_DIR = 6;//!< film rewinder direction output
static constexpr uint8_t PIN_REWINDER_STEP = 7; //!< film rewinder step pulse output
static constexpr uint8_t PIN_TAPE_HOLE_INPUT = 8; //!< tape hole detection photo-interrupter input
static constexpr uint8_t PIN_TENSION_SENS_INPUT = 9; //!< film tension detection photo-interrupter input

// pin functions
static void init_pins(void)
{
  pinMode(PIN_FEED_BUTTON, INPUT_PULLUP);
  pinMode(PIN_FEED_INPUT, INPUT_PULLUP);
  pinMode(PIN_TAPE_HOLE_INPUT, INPUT_PULLUP);
  pinMode(PIN_TENSION_SENS_INPUT, INPUT_PULLUP);

  pinMode(PIN_GEAR_DIR, OUTPUT);
  pinMode(PIN_GEAR_STEP, OUTPUT);
  pinMode(PIN_REWINDER_DIR, OUTPUT);
  pinMode(PIN_REWINDER_STEP, OUTPUT);
}

static bool is_feed_button_pressed()
{
  return !digitalRead(PIN_FEED_BUTTON);
}

//static bool is_feed_input_active();

/*
 * Step the stepper. *_diretion can be:
 * -1: step backward
 *  0: do not step
 *  1: step forward
 */
static void step_stepper(char gear_direction, char rewinder_direction)
{
  digitalWrite(PIN_GEAR_DIR, gear_direction > 0);
  digitalWrite(PIN_REWINDER_DIR, rewinder_direction < 0);
  _delay_us(0.3);
  if(gear_direction != 0) digitalWrite(PIN_GEAR_STEP, 1);
  if(rewinder_direction != 0) digitalWrite(PIN_REWINDER_STEP, 1);
  _delay_us(1);
  digitalWrite(PIN_GEAR_STEP, 0);
  digitalWrite(PIN_REWINDER_STEP, 0);
// _delay_us(1);
}

static bool is_tape_hole_active(void)
{
  return !digitalRead(PIN_TAPE_HOLE_INPUT);
}

static bool is_tension_sens_active(void)
{
  return digitalRead(PIN_TENSION_SENS_INPUT);
}

// interrupt on change setup
static volatile bool feed_signal_active = false; //!< indicates whether the either of button and feed input signal is activaed
static bool is_feed_signal_active(void)
{
  cli();
  bool active = feed_signal_active;
  feed_signal_active = false;
  sei();
  return active;
}


static void init_ioc(void)
{
  EICRA = _BV(ISC01) /*| ISC00*/ ; // The falling edge of INT0 generates an interrupt request.
  EIMSK = _BV(INT0);
  EIFR = 0;
}

ISR (INT0_vect) // handle pin change interrupt for falling edge of INT0
{
  feed_signal_active = true;
}

// timer setup
static volatile bool timer_flag = false;
static bool is_timer_flag_active(void)
{
  cli();
  bool active = timer_flag;
  timer_flag = false;
  sei();
  return active;
}

static void timer1_func(void)
{
  timer_flag = true;
}

static void init_timer1(void)
{
  Timer1.initialize(1000);
  Timer1.attachInterrupt(&timer1_func);
}

// main loop
// simple continuation implementation
#define ____YIELD2(COUNTER) \
	do { \
	state = COUNTER; \
	return; \
	case COUNTER:; \
	} while(0)

#define YIELD ____YIELD2(__COUNTER__)


static constexpr uint8_t mortor_speed_wait = 10;

static void routine()
{
	static uint8_t state = 0;
  static uint8_t i = 0;
  static uint8_t tape_hole_state = 0;
	switch(state)
	{
	default:
		YIELD;

    // IDLE state
    Serial.println(F("S: Idle"));
    while(!is_feed_signal_active())
      YIELD;

    // Feed signal active. First, step gear stepper until tape hole signal is gone.
    Serial.println(F("S: Feed signal received"));
    Serial.println(F("S: Gear forwading until tape hole is not being detected"));
    for(;;)
    {
      tape_hole_state <<= 1;
      tape_hole_state |= is_tape_hole_active();
      if((tape_hole_state & 0x03) == 0x00) break; // break if successive two hole state is low (no hole)
      step_stepper(1, 0);
      for(i = 0; i < mortor_speed_wait; ++i) while(!is_timer_flag_active()) YIELD;
    }

    // Then, step gear stepper until tape hole signal gets active.
    Serial.println(F("S: Gear forwading until tape hole is being detected"));
    for(;;)
    {
      tape_hole_state <<= 1;
      tape_hole_state |= is_tape_hole_active();
      if((tape_hole_state & 0x03) == 0x03) break; // break if successive two hole state is high (hole exist)
      step_stepper(1, 0);
      for(i = 0; i < mortor_speed_wait; ++i) while(!is_timer_flag_active()) YIELD;
   }

    // Then, check film rewinder tension. If tension is low, rewind.
    Serial.println(F("S: Film rewinding"));
    while(!is_tension_sens_active())
    {
      step_stepper(0, 1);
      for(i = 0; i < mortor_speed_wait; ++i) while(!is_timer_flag_active()) YIELD;
    }

    state = 0; // goto start
  }
}

// other arduino stuff
void setup() {
  // put your setup code here, to run once:
  Serial.begin(115200);
  init_pins();
  init_ioc();
  init_timer1();
}

void loop() {
  

  static unsigned long tick = 0;

  // put your main code here, to run repeatedly:
  routine();

  unsigned long mi = millis();
  if(mi != tick)
  {
    tick = mi;
    // every 1ms :
    static uint8_t bounce = 0;
    // do debouncing
    if(is_feed_button_pressed())
    {
      if(bounce > MAX_BOUNCE)
      {
        ; // do nothing
      }
      else if(bounce == MAX_BOUNCE)
      {
        ++bounce;
        feed_signal_active = true; // inform that the button is pressed
      }
      else
      {
        ++bounce;
      }
    }
    else
    {
      bounce = 0;
    }
    
  }


}
