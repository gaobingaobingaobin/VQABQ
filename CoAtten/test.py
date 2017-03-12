import json
import matplotlib.pyplot as plt
import matplotlib.image as mpimg
from evaluate import VQAEvaluator

images_folder = '/home/modar/test2015/'
devtest = '/home/modar/VQA/data/OpenEnded_mscoco_test-dev2015_basic_questions.json'
output_file = '/home/modar/VQA/data/devtest/dev_test2015_answers_5.json'

def concat0(question, basic):
	#No concatenation
	return question

def concat1(question, basic):
	#Appending the questions that is not
	#exactly the main question and with score > 0
	#then take the first 26 words in the concatenation
	basic = [b for b in basic if b['score']>0]
	basic = [b['question'] for b in basic]
	if basic[0]==question:
		basic = basic[1:]
	return question+' '+' '.join(basic)

def concat2(question, basic):
	#Take the questions that is not
	#exactly the main question and with score > 0
	#then take the first 26 unique words in the concatenation
	basic = [b for b in basic if b['score']>0]
	basic = [b['question'] for b in basic]
	if basic[0]==question:
		basic = basic[1:]
	strn = question+' '+' '.join(basic)
	strn = list(set(strn.split(' ')))
	return ' '.join(strn)

def concat3(question, basic):
	#Concatenate the top basic questions without the main question
	basic = [b for b in basic if b['score']>0]
	basic = [b['question'] for b in basic]
	return ' '.join(basic)

def concat4(question, basic):
	#leave the main question alone 
	#and concatenate the union of the words in the basic questions
	basic = [b for b in basic if b['score']>0]
	basic = [b['question'] for b in basic]
	strn = ' '.join(basic)
	strn = list(set(strn.split(' ')))
	return ' '.join(strn)

def concat5(question, basic):
	#the main question with the top question only
	basic = [b for b in basic if b['score']>0]
	basic = [b['question'] for b in basic]
	if basic[0]==question:
		if len(basic)>=2:
			basic = basic[1]
		else:
			basic = ''
	else:
		basic = basic[0]
	return question+' '+basic

def concat6(question, basic):
	#the main question with the top two questions
	basic = [b for b in basic if b['score']>0]
	basic = [b['question'] for b in basic]
	if basic[0]==question:
		basic = basic[1:3]
	else:
		basic = basic[0:2]
	return question+' '+' '.join(basic)


#pick your concatenation method
method = concat5

with open(devtest, 'r') as f:
	dataset = json.load(f)
#dataset = dataset[10:100]

vqa = VQAEvaluator(concatenate=method)

data = vqa.evaluate(dataset, images_folder)
with open(output_file, 'w') as f:
	json.dump(data, f)

def show(i, view=True):
	question = dataset[i]['question']
	basic = dataset[i]['basic']
	concatenated = method(question, basic)
	answer = data[i]['answer']
	print('Question: '+question)
	print('Concatenated: '+concatenated)
	print('Answer: '+answer)
	if view:
		image_file = images_folder+dataset[i]['image_path']
		image = mpimg.imread(image_file)
		plt.imshow(image)
		plt.show()

#now try
#show(0)