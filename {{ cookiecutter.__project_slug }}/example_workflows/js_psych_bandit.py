"""
Bandit Workflow
    Reward Trajectory as Conditions
    Theorist: Rnn Sindy Theorist
    Experimentalist: Random Sampling + Model Disagreement
    Runner: Synthetic + Firebase Runner + Prolific recruitment)
"""

# *** IMPORTS *** #

# Python Core
from dataclasses import dataclass, field
from typing import List
import random, json

# External Vendors
import pandas as pd
import numpy as np
from sklearn.base import BaseEstimator
import torch

# General AutoRA
from autora.variable import VariableCollection, Variable
from autora.state import StandardState, on_state, Delta

# Experimentalists
from autora.experimentalist.bandit_random import bandit_random_pool
from autora.experimentalist.model_disagreement import model_disagreement_sampler_custom_distance

# Experiment Runner
from autora.experiment_runner.synthetic.psychology.q_learning import q_learning
from autora.experiment_runner.firebase_prolific import firebase_runner, firebase_prolific_runner

# Theorist
from autora.theorist.rnn_sindy_rl import RNNSindy
from autora.theorist.rnn_sindy_rl.utils.parse import parse as parse_equation

# *** CONSTANTS *** #

RUNNER_TYPE = 'synthetic'  # Options: synthetic, firebase, prolific

TRIALS_PER_PARTICIPANTS = 100
SAMPLES_PER_CYCLE = 1
PARTICIPANTS_PER_CYCLE = 40
CYCLES = 4
INITIAL_REWARD_PROBABILITY_RANGE = [.2, .8]
SIGMA_RANGE = [.2, .2]

EPOCHS = 10 # 100



seed = 11

# for reproducible results:
if seed is not None:
    np.random.seed(seed)
    torch.manual_seed(seed)

# *** AUTORA SETUP *** #

# ** Set up variables ** #
# independent variable is "reward-trajectory": A 2 x n_trials Vector with entries between 0 and 1
# dependent variable is "choice-trajectory": A 2 x n_trials Vector with boolean entries (one hot encoded)

variables = VariableCollection(
    independent_variables=[Variable(name="reward-trajectory")],
    dependent_variables=[Variable(name="choice-trajectory")]
)

# State
# We use a non-standard state by extending the standard state with an additional model
@dataclass(frozen=True)
class RnnState(StandardState):
    models_additional:  List[BaseEstimator] = field(
        default_factory=list,
        metadata={"delta": "extend"},
    )

# initialize the state:
state = RnnState(variables=variables)

# *** AUTORA COMPONENTS/AGENTS *** #
# Components are functions that run on the state. The main components are:
# - theorist
# - experiment-runner
# - experimentalist
# See more about components here: https://autoresearch.github.io/autora/

# ** Experimentalists ** #
# * Random Pool * #
# Create a pooler on state that creates a pool of conditions. Here, we use the bandit sampler to create
# reward-trajectories

@on_state()
def pool_on_state(num_samples, n_trials=TRIALS_PER_PARTICIPANTS):
    """
    This is creates `num_samples` randomized reward-trajectories of length `n_trials`
    """
    sigma = np.random.uniform(SIGMA_RANGE[0], SIGMA_RANGE[1])
    trajectory_array = bandit_random_pool(
        num_rewards=2,
        sequence_length=n_trials,
        initial_probabilities=[INITIAL_REWARD_PROBABILITY_RANGE, INITIAL_REWARD_PROBABILITY_RANGE],
        sigmas=[sigma, sigma],
        num_samples=num_samples
    )
    trajectory_df = pd.DataFrame({'reward-trajectory': trajectory_array})
    return Delta(conditions=trajectory_df)

# * Model Disagreement Sampler * #
# In addition to the pool, we also use a model disagreement sampler, that choses conditions based
# on their predicted disagreement between two models.

# Custom distance function
# Since the predictions of a model has a non-standard format (it isn't a single number), we need to
# create a custom distance function. The prediction for a model is a list of two-dimensional vectors:
# array([[0.5, 0.5], [0.68..., 0.31...], ...]).

def custom_distance(prob_array_a, prob_array_b):
    return np.mean([(prob_array_a[0] - prob_array_b[0])**2 + (prob_array_a[1] - prob_array_b[1])**2])

# We can now use the custom_distance function in our sampler:

@on_state()
def model_disagreement_on_state(
        conditions, models, models_additional, num_samples):
    conditions = model_disagreement_sampler_custom_distance(
        conditions=conditions['reward-trajectory'],
        models=[models[-1], models_additional[-1]],
        distance_fct=custom_distance,
        num_samples=num_samples,
    )
    return Delta(conditions=conditions)


# ** Experiment Runner ** #
# * Synthetic Runner * #
# This is a synthetic runner to test the autora workflow before deploying on prolific

runner = q_learning()

@on_state()
def runner_on_state_synthetic(conditions):
    choices, choice_probabilities = runner.run(conditions, return_choice_probabilities=True)
    experiment_data = pd.DataFrame({
        'reward-trajectory': conditions['reward-trajectory'].tolist(),
        'choice-trajectory': choices,
        'choice-probability-trajectory': choice_probabilities
    })
    return Delta(experiment_data=experiment_data)

# * Runner on Firebase/Prolific * #

# firebase credentials
firebase_credentials = {
    "type": "type",
    "project_id": "project_id",
    "private_key_id": "private_key_id",
    "private_key": "private_key",
    "client_email": "client_email",
    "client_id": "client_id",
    "auth_uri": "auth_uri",
    "token_uri": "token_uri",
    "auth_provider_x509_cert_url": "auth_provider_x509_cert_url",
    "client_x509_cert_url": "client_x509_cert_url"
}

# time between checks
sleep_time = 30

# Study name: This will be the name that will appear on prolific, participants that have participated in a study with the same name will be
# excluded automatically
study_name = 'my autora experiment'

# Study description: This will appear as study description on prolific
study_description= 'Two bandit experiment'

# Study Url: The url of your study (you can find this in the Firebase Console)
study_url = 'www.my-autora-experiment.com'

# Study completion time (minutes): The estimated time a participant will take to finish your study. We use the compensation suggested by Prolific to calculate how much a participant will earn based on the completion time.
study_completion_time = 5

# Prolific Token: You can generate a token on your Prolific account
prolific_token = 'my prolific token'

# Completion code: The code a participant gets to prove they participated. If you are using the standard set up (with cookiecutter), please make sure this is the same code that you have providede in the .env file of the testing zone.
completion_code = 'my completion code'

experiment_runner_firebase = firebase_runner(
    firebase_credentials=firebase_credentials,
    time_out=study_completion_time,
    sleep_time=sleep_time)

experiment_runner_prolific = firebase_prolific_runner(
            firebase_credentials=firebase_credentials,
            sleep_time=sleep_time,
            study_name=study_name,
            study_description=study_description,
            study_url=study_url,
            study_completion_time=study_completion_time,
            prolific_token=prolific_token,
            completion_code=completion_code,
        )

# This function transforms a condition (the output of a experimentalist) to a trial sequence, that
# is readable by the jsPsych experiment. jsPsych expects a trial sequence in the following format:
# trial_sequence = {'feature_a': [1, 2, 3, ...], 'feature_b': ['red', 'green', ...], ...}
def _condition_to_trial_sequence(conditions):
    """
    Transforms conditions created by the experimentalist in a list of trial sequences
    """
    trial_sequences = []
    for c in conditions['reward-trajectory'].tolist():
        sequence = []
        if len(c) % 2:
            print('WARNING: trajectory has an odd number of entries. ')

        # create a counterbalanced position list:
        _n = len(c) // 2
        pos_list = [['left', 'right']] * _n + [['right', 'left']] * _n
        random.shuffle(pos_list)

        # a condition c is a list of values (c = [[0, 1], [1, 1], [0, 0], ...])
        for idx, trial in enumerate(c):
            sequence.append({'values': trial.tolist(), 'pos': pos_list[idx]})
        trial_sequences.append(sequence)
    return trial_sequences

# We also have to transform the data returned by the jsPsych script back to experiment data.
def _jsPsych_to_experiment_data(data):
    result = []
    # For the output format of the jsPsych script, see the return value in testing_zone/src/design/main.js
    for item in data:
        parsed = json.loads(item)
        condition = json.loads(parsed['condition'])
        observation = parsed['observation']
        c_subj = {'reward-trajectory': [], 'choice-trajectory': []}
        for c, o in zip(condition, observation['values']):
            t = c['values']
            c_subj['reward-trajectory'].append(t)
            if o == 0:
                c_subj['choice-trajectory'].append([1, 0])
            else:
                c_subj['choice-trajectory'].append([0, 1])

        c_subj['reward-trajectory'] = np.array(c_subj['reward-trajectory'])
        c_subj['choice-trajectory'] = np.array(c_subj['choice-trajectory'])
        result.append(c_subj)
    return result

# runner on firebase (for testing before uploading to prolific)
@on_state()
def runner_on_state_firebase(conditions):
    trial_sequences = _condition_to_trial_sequence(conditions)
    data = experiment_runner_firebase(trial_sequences)
    experiment_data = _jsPsych_to_experiment_data(data)
    return Delta(experiment_data=experiment_data)

@on_state()
def runner_on_state_prolific(conditions):
    trial_sequences = _condition_to_trial_sequence(conditions)
    data = experiment_runner_prolific(trial_sequences)
    experiment_data = _jsPsych_to_experiment_data(data)
    return Delta(experiment_data=experiment_data)

# ** Theorist ** #
# Here we use a Sindy-RNN regression as theorist. This theorist is a custom theorist that finds learning
# equations for bandit tasks. Here, we create two theorist that impose different restrictions on the
# equations (degree of polynomials is 2 or 1)

theorist = RNNSindy(2, epochs=EPOCHS, polynomial_degree=2)
theorist_additional = RNNSindy(2, epochs=EPOCHS, polynomial_degree=1)

@on_state()
def theorist_on_state(experiment_data):
    x = experiment_data['reward-trajectory']
    y = experiment_data['choice-trajectory']
    return Delta(models=[theorist.fit(x, y)])


@on_state()
def theorist_additional_on_state(experiment_data):
    x = experiment_data['reward-trajectory']
    y = experiment_data['choice-trajectory']
    return Delta(models_additional=[theorist_additional.fit(x, y)])


# *** LOOP *** #
# With all the components defined, we can run a the experiment in a loop:

for c in range(1, CYCLES + 1):

    if len(state.models) > 0:
        state = pool_on_state(state, num_samples=20)
        state = model_disagreement_on_state(state, num_samples=SAMPLES_PER_CYCLE)
    else:
        state = pool_on_state(state, num_samples=SAMPLES_PER_CYCLE)

    if RUNNER_TYPE == 'synthetic':
        state = runner_on_state_synthetic(state)
    elif RUNNER_TYPE == 'firebase':
        state = runner_on_state_firebase(state)
    elif RUNNER_TYPE == 'prolific':
        state = runner_on_state_prolific(state)

    state = theorist_on_state(state)
    state = theorist_additional_on_state(state)

    model = state.models[-1]
    model_additional = state.models_additional[-1]

    equations_model = parse_equation(model)
    equation_model_additional = parse_equation(model_additional)

    print('# MODEL DEGREE = 2#')
    print(f'chosen: {equations_model[0]}')
    print(f'non chosen: {equations_model[1]}')

    print('# MODEL DEGREE = 1#')
    print(f'chosen: {equation_model_additional[0]}')
    print(f'non chosen: {equation_model_additional[1]}')

